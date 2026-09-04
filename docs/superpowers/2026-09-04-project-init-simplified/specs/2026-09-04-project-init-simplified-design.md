# Gita 项目初始化 · 极简双入口

> 日期：2026-09-04  
> 状态：已确认，实现计划见 [2026-09-04-project-init-simplified.md](../plans/2026-09-04-project-init-simplified.md)  
> 产品依据：[项目初始化流程 PRD v1.1](../../../../../1-产品&设计/2-产品PRD/记录/2026-08-29-Gita-项目初始化流程-PRD.md)、[Gita 记录 PRD v1.1](../../../../../1-产品&设计/2-产品PRD/记录/Gita-记录-PRD.md)  
> 视觉依据：[Figma · Flow / Project Initialization · Simplified](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd/%E5%90%89%E4%BB%96%E8%AE%AD%E8%AE%B0app?node-id=733-2)（文案与布局以该节点为准）  
> 取代：[2026-08-29 项目初始化视觉对齐](../../2026-08-29-project-init-visual/specs/2026-08-29-project-init-visual-design.md)（Ready 页、目标必填、创建页收类型/阶段/重点）

**成功标准：** 用户只填项目名称就能建项目；创建成功直接进入项目详情，不再经过 Ready；可以从项目页或一条既有练习两条路径创建；项目页创建不制造练习事实；完成标准和当前阶段可在详情后补。

---

## 1. 背景与目标

`foxgita` 已能创建项目，但创建页仍要求名称 + 完成目标，并展示类型、阶段、当前重点。空状态创建成功会进入 `ProjectReadyView`，主按钮是「创建今天的练习项」。练习详情的「新建并加入」弹出同一套重表单。用户在尚未开始项目时通常填不准这些字段。

本期把首次创建收成一件事：建立一个可承载后续练习的长期上下文。其余信息随练习在项目详情后补。

### 做

- 项目空状态与列表入口改为「新建项目」，文案对标 Figma 空状态。
- 创建 / 编辑共用极简表单：名称必填，完成标准默认折叠。
- 新「从练习创建」页：完成页和练习详情进入；预填练习标题；「创建并加入」/「仅创建空项目」。
- 删除 `ProjectReadyView` 与 `RecordRoute.projectReady`。所有创建成功 replace 为项目详情 + Toast「项目已创建」。
- 无练习的项目详情对标 Figma 空状态，主按钮「开始第一次练习」。
- 详情可编辑完成标准和当前阶段。类型、当前重点、封面仍 P1。
- 规则、Store、埋点、测试与上述行为对齐。

### 不做

- Schema 迁移，或把 `goal` 改名为 `completionCriteria`。
- 类型、当前重点、封面的详情编辑。
- 云同步、服务端幂等键、跨会话草稿。
- AI 建议名称 / 完成标准。
- 一条练习多项目。
- 改 `project.pbxproj`（新 Swift 文件由 synchronized group 接入）。
- 重做完成 / 归档 / 删除，或练习主页项目快捷入口。

---

## 2. 产品与工程决策

| 项 | 选择 |
|---|---|
| 创建 UI | 两页：一句话创建（空状态 / 列表 / 编辑）+ 从练习创建。不在 `ProjectEditorView` 上堆第三种皮肤 |
| 成功落点 | 删除 Ready。创建成功一律 `replaceLastRecordRoute(.projectDetail)` |
| 编辑 | 与创建同一极简表单，只改名称和完成标准，不得清空详情里已有的阶段 / 类型 / 重点 |
| 详情后补 | 本期可改完成标准、当前阶段；类型 / 重点 / 封面 P1 |
| 从练习入口 | 练习详情关联区 + 练习 Tab 刚刚完成卡 |
| 名称预填 | 练习标题原文，用户可清空或修改。不做「学会《曲名》」抽取 |
| 数据字段 | 继续用 `Project.goal`；界面写「完成标准」 |
| 关联失败 | 项目已创建则保留，只重试 `setPracticeItemProject`，不得再 insert 一个项目 |
| 弱网 | 不新增事务队列。本地 SwiftData：先 `createProject`，再关联 |

---

## 3. 架构与导航

底部仍是 `练习 | 记录 | 设置`。记录首页仍是 `练习 | 项目`。

```text
记录 / 项目空状态 ──新建项目──► ProjectEditorView(create)
记录 / 项目列表 ──新建项目──► ProjectEditorView(create)
项目详情 ──编辑──► ProjectEditorView(edit) ──保存 pop──► 详情

练习详情「建立长期项目」──► ProjectCreateFromPracticeView(itemId)
练习 Tab 刚刚完成卡「建立长期项目」──► 同上

创建成功 ──replace──► ProjectDetailView + Toast「项目已创建」
练习 Tab sheet 创建成功 ──► selectedTab = record，recordPath = [projectDetail]
```

### 3.1 路由

`RecordRoute`：

- 保留 `projectCreate`。去掉 `fromEmpty`。空状态和列表进同一页，成功都进详情。
- 新增 `projectCreateFromPractice(itemId: UUID)`。
- 保留 `projectEdit` / `projectDetail`。
- 删除 `projectReady`。

`AppRouter.pendingJoinPracticeItemId` 删除。关联目标只来自 `projectCreateFromPractice(itemId:)`。

练习 Tab 现有 `showCreateProjectSheet` + `ProjectEditorView` 改为呈现 `ProjectCreateFromPracticeView`。成功后切到记录 Tab 的项目详情，并把 `recordSegment` 设为 `.project`，使详情返回落在项目分段。

### 3.2 栈规则

1. 空状态 / 列表 → push `projectCreate`。
2. 保存成功 → **替换**栈顶为 `projectDetail(projectId:)`。创建页离开栈，返回不会回到填过的表单。
3. 从练习（记录栈）→ push `projectCreateFromPractice`；成功同样替换为详情。
4. 编辑 → pop 回详情，不 replace。
5. 「仅创建空项目」同样进新项目详情；当前练习 `projectId` 不变。
6. 「开始第一次练习」成功 → 替换栈顶为练习详情（与现 Ready / 项目详情创建今天练习项相同）。失败留在项目详情，项目已存在，可重试。

### 3.3 现有代码对照

| 现有 | 本期 |
|---|---|
| `ProjectEditorView` 名称+目标必填，类型/阶段/重点 | 收成名称 + 折叠完成标准 |
| `fromEmpty` → `projectReady` | 删除 Ready；一律进详情 |
| `pendingJoinPracticeItemId` + 同一创建页 | 独立从练习页，itemId 在路由上 |
| `ProjectReadyView`「创建今天的练习项」 | 无练习详情主按钮「开始第一次练习」 |
| 练习详情「新建并加入」 | 「建立长期项目」打开从练习页 |
| `JustCompletedCard` 已实现但未接入 | 练习完成成功后接到练习 Tab，并加建立项目入口 |

---

## 4. 页面与文案

界面文案以 Figma `733:2` 四屏为准，不沿用 PRD 里与稿不一致的「创建项目」导航标题。

### 4.1 项目空状态

对标 `Gita / Record Projects / Empty · Simplified`。

- 徽章：跨天练习目标
- 标题：把多天练习放进一个项目
- 说明：以后可以从上次状态继续，练习记录会自然汇集到这里。
- 主按钮：新建项目 → `projectCreate`
- 次要：暂不创建，继续自由练习 → `recordSegment = .practice`，不写数据
- 脚注：项目不会改变已有练习，也不会要求所有练习加入项目

列表非空状态的右上 / 主入口同步为「新建项目」，进同一创建页。空状态条件不变：当前档案没有任何 `deletedAt == nil` 的 Project。

### 4.2 一句话创建 / 编辑

对标 `Gita / Project Setup / Quick Create`。

- 导航：创建为「新建项目」，编辑为「编辑项目」。返回 / 关闭在已输入时确认「继续填写 / 放弃创建」。
- 问句：你想持续练什么？
- 说明：用一句话创建，其他信息以后再补充。
- 字段：项目名称 *（1–40，placeholder 学会《知足》）
- 折叠行：＋ 添加完成标准　选填 ›。展开后选填文本框，最长 120。编辑时若 `goal` 非空则默认展开。
- 底部：只需要一个项目名称；主按钮创建为「创建项目」，编辑为「保存」
- 删除类型 chips、阶段选择、当前重点输入

名称为空时禁用主按钮。提交中禁用并保持 loading。

### 4.3 新项目详情（0 条有效练习）

对标 `Gita / Project Detail / New Empty`。有效练习判定沿用 `PracticeItemRules.isEffective`。

- 导航：项目详情；更多菜单保留现有完成 / 删除等，编辑改为打开极简编辑页
- 身份：名称、进行中、刚刚创建 · 还没有练习记录
- 后补行：完成标准　添加 ›（已有则展示摘要）；当前阶段　未设置 ›（已有则展示阶段名）。点完成标准打开半页 sheet（单文本框 + 保存，允许空表示清除）。点阶段打开现有阶段列表。
- 空状态卡：第一次 / 从一次真实练习开始 / 练习完成后，时间、笔记和录音会汇集到项目里。
- 底部：项目已创建，可以稍后再练；主按钮「开始第一次练习」

有至少一条有效练习后，主按钮改回现有「创建今天的练习项」，空状态卡换成现有上次证据 / 这次练什么。不在有练习时继续显示「开始第一次练习」。

阶段选项沿用 `ProjectSetupRules.stages`：熟悉内容、分段练习、串联整首、稳定演奏、完成，可「不选择」。

### 4.4 从练习创建

对标 `Gita / Project Setup / From Practice`。

- 导航：建立长期项目
- 问句：把这次练习持续下去
- 来源卡：来自今天的练习（非今日则用来源练习的 `practiceDay` 文案）；标题；`{分钟} · 已保存 n 条录音`（无录音则省略后段，沿用 `JustCompletedCopy`）
- 项目名称 *：预填该练习 `title` 原文，可清空或修改
- 说明：这次练习会自动加入项目。完成标准和阶段可以稍后补充。
- 主按钮：创建并加入项目
- 次要：仅创建空项目

本页不展示完成标准折叠。完成后补放到详情。

已关联项目时，点「创建并加入」先确认：这条练习已属于「{原项目名}」，加入新项目后会从原项目移除。取消留在本页；确认后再创建并换归属。

### 4.5 从练习的两个入口

**练习详情关联区：** 未关联时把「新建并加入」换成「建立长期项目」，打开从练习页。加入现有项目 / 更换 / 移出保持不变。已关联时，菜单另留「建立长期项目」，走同一确认更换流程。

**练习完成入口：** 现有 `JustCompletedCard` 未挂到主页。`lastCompletedSessionId` 在生产路径从未赋值。本期：

1. 把未使用的 `lastCompletedSessionId` 换成 `lastCompletedPracticeItemId: UUID?`。练习详情「完成」成功后写入该项 id。
2. 练习 Tab 今天视图展示刚刚完成卡：主操作仍是「再练一次 / 查看记录」。未关联时在按钮下加文字链「建立长期项目」。
3. 已关联则完成卡不展示该入口；更换归属只走练习详情。

---

## 5. 数据规则

不改 Schema。Project / PracticeItem 字段保持 V12。

### 5.1 创建

`createProject(name:goal:now:)` 只接收名称和完成标准。`kindRaw` / `stageRaw` / `currentFocus` 写 `""`，`status = active`。

`ProjectSetupRules.prepare`：

- 名称 trim 后 1–40，否则 `nameEmpty` / `nameTooLong`
- 完成标准 trim 后 0–120，空串合法，不再 `goalEmpty`
- `currentFocus` 从创建 / 编辑校验中移除（详情 P1 再写）

同名允许。创建项目不 insert PracticeItem。

### 5.2 编辑

新增 `updateProjectBasics(id:name:goal:now:)`：只改 `name`、`goal`、`updatedAt`。禁止经极简编辑页写入 `kindRaw` / `stageRaw` / `currentFocus`。

现有 `updateProject` 全量签名若仍被详情阶段 / 其他调用使用，调用方必须传入当前值；极简编辑不得走这条把空字符串写回去的路径。

详情后补：

- `updateProjectGoal(id:goal:now:)`
- `updateProjectStage(id:stageRaw:now:)`（`""` 表示未设置）

### 5.3 练习关联

| 动作 | 写入 |
|---|---|
| 项目页创建 | 仅 Project |
| 创建并加入 | Project + `PracticeItem.projectId = 新项目 id` |
| 仅创建空项目 | 仅 Project |
| 开始第一次练习 / 创建今天的练习项 | 新 PracticeItem：`practiceDayKey = 本地今天`，`projectId` 已有项目，标题 `titleForNewPracticeItem`（重点空则用名称），`durationSeconds = 0` |

不复制练习项，不改日期、时长、笔记、媒体、打卡。一条练习最多一个项目。删除项目只解绑。

关联失败：View 持有已创建 `projectId`；重试只调用 `setPracticeItemProject`。用户返回时项目已在列表中。

### 5.4 Dirty

创建：名称或完成标准 trim 后非空。从练习页：名称与预填不同才算 dirty。预填未改直接返回，不弹放弃确认。

---

## 6. 失败与状态

| 状态 | 行为 |
|---|---|
| 名称无效 | 就地错误，保留输入 |
| 提交中 | 主按钮 loading，忽略再点 |
| 创建失败 | 保留表单，提示重试 |
| 关联失败 | 项目保留，提示「项目已创建，加入失败，请重试」；重试键只做关联 |
| 已关联确认 | 取消不创建；确认后创建并更换 |
| 第一次练习创建失败 | 留在详情，不出现半成品练习项 |
| 弱网 | 与现网相同：本地 persist 失败则整步失败，表单不丢 |

进程内提交锁。被杀后锁消失，再点算新意图；不引入跨启动幂等键。

---

## 7. 埋点

沿用并调整 `RecordAnalytics`。禁止上传项目名称、完成标准、练习标题或笔记原文。

| 事件 | 关键属性 |
|---|---|
| `project_create_entry_viewed` | `source`: `projects_empty` / `projects_list` / `practice_detail` / `practice_complete` |
| `project_create_started` | `source` |
| `project_goal_expanded` | `source`（仅一句话创建 / 编辑） |
| `project_create_submitted` | `source`, `has_goal` |
| `project_created` | `source`, `has_goal`, `duration_ms` |
| `project_created_from_practice` | `link_result`: `linked` / `empty_only` / `link_failed`, `had_previous_project` |
| `project_create_failed` | `source`, `error_code` |
| `project_detail_first_practice_clicked` | `project_id`（无练习态主按钮） |

删除依赖 `fromEmpty`、`projectReadyViewed`、`projectReadyActionClicked` 的事件，或停止发送。`hasFocus` 不再作为创建提交属性。

---

## 8. 测试

### 8.1 规则

改 `ProjectSetupRulesTests`：

- `prepare` 接受空 goal；超长 goal 仍失败
- 删除 / 不再期望 `goalEmpty`
- dirty 只看名称和完成标准
- 从练习预填：名称仍等于进入时的 title 则不算 dirty

Store：

- `createProject` 在只给名称时成功，kind/stage/focus 为空
- `updateProjectBasics` 不改已有 `stageRaw`
- 创建并加入只改 `projectId`；关联抛错时项目仍能按 id 读到
- 仅创建空项目不改练习 `projectId`

### 8.2 导航

- 删除 `projectReady` 后工程可编译
- 空状态、列表、从练习三条成功路径落到 `projectDetail`
- 练习 Tab 从练习创建成功后 `selectedTab == .record` 且栈顶为详情
- 编辑保存 pop，不是 replace

### 8.3 回归

- 有练习的项目详情「创建今天的练习项」、轨迹、累计分钟
- 删除项目后练习仍在原日期且 `projectId` 为空
- 同名两个项目按 id 打开各自轨迹
- 自由练习完成率路径不被空状态阻断

---

## 9. 文件边界

| 文件 | 变化 |
|---|---|
| `AppRouter.swift` | 路由；删除 pending join 与 Ready |
| `ProjectSetupRules.swift` | goal 选填；dirty 收窄 |
| `ProjectEditorView.swift` | 极简创建 / 编辑 |
| `ProjectCreateFromPracticeView.swift` | 新建 |
| `ProjectReadyView.swift` | 删除 |
| `ProjectDetailView.swift` | 无练习空状态；goal/stage 后补；第一次练习 CTA |
| `RecordView.swift` | 空状态文案；路由分发 |
| `PracticeDetailView.swift` | 建立长期项目；完成时记录 item id |
| `JustCompletedCard.swift` + `PracticeView.swift` | 接入完成卡与建立入口 |
| `PracticeStore.swift` | create 签名收窄；basics / goal / stage 更新 |
| `RecordAnalytics.swift` | 事件属性 |
| `ProjectSetupRulesTests` 及 Store / Router 测试 | 同步 |

---

## 10. 发布验收清单

- [ ] 项目名称是创建 / 编辑唯一必填项
- [ ] 完成标准默认折叠，可在详情后补
- [ ] 创建 / 编辑页没有类型、阶段、当前重点、封面
- [ ] 创建成功直接进详情，没有 Ready 页
- [ ] 项目页创建不生成练习项、时长或打卡
- [ ] 无练习详情主按钮为「开始第一次练习」
- [ ] 完成页和练习详情都能从该练习建项目
- [ ] 创建并加入不复制、不改写练习事实
- [ ] 仅创建空项目不改变当前练习归属
- [ ] 编辑名称 / 完成标准不清空已有阶段
- [ ] 关联失败可重试且不产生第二个项目
- [ ] 自由练习入口未被阻断
- [ ] 埋点不含用户输入原文
