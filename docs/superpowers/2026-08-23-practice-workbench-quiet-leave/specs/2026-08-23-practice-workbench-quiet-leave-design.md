# Design: 练习工作台（返回静默保存 + 完成不弹卡片）

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-23  
**状态：** Draft  
**方案：** 方案 B — 一条保存路径；完成不再写成果卡 id；首页不渲染「刚刚完成」  
**升级对象：** [练习工作台上次速度与当场回放](../../2026-08-23-practice-workbench-resume/specs/2026-08-23-practice-workbench-resume-design.md) 中「返回确认框」「完成写 lastCompletedSessionId / 成果卡」  
**不改：** 进入恢复 BPM / 焦点行、当场播放、`finishSession -> String?`、Schema

---

## 1. 背景与目标

刚合入的工作台切片里：返回在「已有 session」时才会安静保存；计时、笔记、待写入媒体若还没开 session，会弹出确认框。完成会把 session id 交给首页，今日练习弹出「刚刚完成」。

产品要改成：返回默认保存这次留下的一切，不提示；完成不再在今日练习弹卡片。

成功标准：

1. 返回有内容：写入与完成相同的 session 字段（计时、笔记、步骤、BPM、媒体），写回 `task.defaultBpm`，无确认框、无震动、不拉回今天、不写 `lastCompletedSessionId`。
2. 返回空访：不建 session，直接离开。
3. 完成有效：同一条保存，震动，`returnPracticeToToday = true`，不写 `lastCompletedSessionId`。
4. 空完成：toast「这次没有留下记录」，拉回今天，不写 BPM / id。
5. 今日练习不渲染「刚刚完成」，即使 Router 里仍有旧 id。

---

## 2. 产品决策

| 项 | 选择 |
|---|---|
| 返回有内容 | 静默保存，等同完成的落库范围。不弹窗 |
| 返回空访 | 离开。不建记录 |
| 返回导航 | 回到进来时的那天。不设 `returnPracticeToToday` |
| 返回反馈 | 无震动、无 toast、无成果卡 |
| 完成有效 | 同一条保存 + 震动 + 拉回今天。无成果卡 |
| 空完成 | 现有 toast，拉回今天 |
| 成果卡 | 这一轮不展示。不删 `JustCompletedCard` / `JustCompletedCopy` / Router 字段 |
| 保存失败（返回） | 仍离开，不提示 |
| 保存失败（完成） | 保持现状：解除 `isCompleting`，留在详情页 |
| Schema | 不改 |

覆盖 2026-08-23 规格中的对应行：

- 「点返回（已有 session）安静保存」→ **任何有内容的返回都安静保存**，不只是已有 session。
- 「点完成写 lastCompletedSessionId + 成果卡」→ **完成不写 id，首页不画卡片**。

---

## 3. 架构

```text
PracticeDetailView
  persistVisit(task)            共用
    persistPending
    已有 openSessionId → updateOpenSession
    否则有内容 → finishSession
    空访 → 不写

  requestExit
    persistVisit
    leave()                     不写 id，不 returnPracticeToToday
    不再设置 confirmExit

  complete
    persistVisit
    空 → toast + returnPracticeToToday
    有效成功 → haptic + returnPracticeToToday
    不写 lastCompletedSessionId

PracticeView
  不渲染 JustCompletedCard
```

`hasUnsavedWork` 仍是「有内容」口径：计时 > 0，或未写入媒体，或笔记非空，或已有 `openSessionId`。步骤/BPM 单独改动且计时为 0、无笔记、无媒体、无已开 session，仍算空访（与锁定的方案 A 一致）。

不改 `PracticeStore` 签名。`finishSession` 仍返回 `String?`；详情页可丢弃该 id。

---

## 4. 练习详情

`requestExit`：停表、停节拍器、停录，再 `persistVisit`（内部先 `persistPending`），再 `leave()`。删除「`hasUnsavedWork` → `confirmExit = true`」分支。确认框若因此不再被设置，顺带去掉对应 `.alert` / `.confirmationDialog` 绑定（若再无引用）。

`complete`：停表、停播放，再 `persistVisit`。分支：

| 情况 | 行为 |
|---|---|
| 空访 | toast「这次没有留下记录」，`returnPracticeToToday`，pop |
| `updateOpenSession` / `finishSession` 成功 | haptic，`returnPracticeToToday`，pop |
| `finishSession` 返回 `nil`（非空路径失败） | `isCompleting = false`，留下 |

两条路径都不得赋值 `router.lastCompletedSessionId`。

---

## 5. 今日练习

去掉 `justCompleted` 用于渲染的 `if let session = justCompleted { JustCompletedCard(...) }`。不要改成用 `endedAt` 猜最新一条。

`AppRouter.lastCompletedSessionId`、`clearJustCompleted()`、离 Tab / 换日清空可以留着，不再被完成写入，因此首页不会出现卡片。

---

## 6. 错误与边界

- 返回保存失败：离开。不 toast、不确认。
- 完成保存失败：留在详情，可再点完成。
- 从过去日完成：仍靠现有 `returnPracticeToToday` 拉回今天。
- 从过去日返回：不拉回今天。
- 播放、焦点行、进入 BPM 恢复：本规格不改。

---

## 7. 测试

现有 `PracticeStoreTests` 不改口径。

详情页 / 首页以阅读验收 + 现有编译门禁为主。必须成立：

1. `requestExit` 在 `hasUnsavedWork` 时不再设 `confirmExit`。
2. `requestExit` 不写 `lastCompletedSessionId`，不设 `returnPracticeToToday`。
3. `complete` 成功路径设 `returnPracticeToToday`，不写 `lastCompletedSessionId`。
4. `PracticeView` 正文不再出现 `JustCompletedCard`。

不改 `project.pbxproj`。不改 Schema。

---

## 8. 范围外

- 删除 `JustCompletedCard.swift` / `JustCompletedCopy.swift` / Router id 字段
- 步骤或 BPM 单独改动且无计时/笔记/媒体时建 session
- 返回失败也 toast
- 改进入恢复、当场播放
