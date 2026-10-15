# 项目详情 · 先看见进步 (Progress First) — 规格说明书

> 日期：2026-10-15  
> 状态：`ready-for-agent`  
> 目标仓库：`haizei/foxgita`  
> 关联 ADR：[ADR-0009: 采用 Progress-First 架构与定性证据链条](../../../adr/0009-adopt-progress-first-architecture-for-project-detail.md)  
> 视觉依据：[Figma · 05_Product Flow_Recording (Node `624:405` / Frame `1983:2`)](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd/%E5%90%89%E4%BB%96%E8%AE%AD%E8%AE%B0app?node-id=624-405)  
> 领域术语：遵循 `CONTEXT.md` 规范  

---

## Problem Statement

用户在长期攻克一首吉他曲目或练习专项时，很难感知到自己的真实进步。现有项目详情页面仅展示冷冰冰的累计练习分钟数与日期，缺乏有力的听觉证据。用户不知道两周前的自己和今天的自己到底有什么区别，容易陷入枯燥与练琴挫败感。

在设计探索中，虽然尝试过百分比进度条（如“完成度 65%”）和固定打卡路线，但乐器练习并非线性流程，机械的数字打分不仅缺乏准确性，更给用户带来沉重的心理负担。此外，当用户在项目详情中想要开始练琴时，无法顺畅将当前项目的聚焦意图转化为当天的具体练习，导致长期目标与每日行动脱节；练习笔记散落各处，也无法作为同一项目的阶段成长证据进行统一回溯。

---

## Solution

在项目详情中落地“先看见进步（Progress First）”架构，由三屏互联与闭环状态机构成完整成长反馈闭环：

1. **定性里程碑与成长历程 (Project Progress Story)**：
   在项目详情顶部，基于用户实际记录的练习范围，定性展示从局部片段练习到完整演奏的里程碑演进（如「分段练副歌 → 连贯弹唱 → 完整弹唱一遍」），并明确告知用户这是“根据已记录的练习范围 · 非完成度评分”，彻底摒弃百分比与冰冷打分。

2. **最近练习听觉证据 (Last Practice Evidence)**：
   突出展示最近一次有效练习的录音波形与心得反思，用户在卡片内即可一键回听，并提供直达录音对比的入口。

3. **双轨 A/B 录音对比与关键停顿观察 (Audio Comparison)**：
   提供独立的录音对比界面，以用户认可的阶段基准版本与最近录音进行双轨波形呈现，支持 A/B 无缝交替试听。结合 AI 听觉观察标出关键停顿差异的时间戳（例如：阶段版 00:42 停顿明显 vs 最近 00:38 连贯），并关联展示两次练习记录的笔记。

4. **项目到今日练习状态流转 (Project Practice State Handoff)**：
   在“下次练什么”卡片中呈现项目当前重点与指引，点击后根据用户今天是否已开练（未开始 / 已创建未完成 / 已完成）自动分流，预填重点并建立关联，杜绝重复创建空练习。

5. **笔记历史只读投影 (Project Note Projection)**：
   在项目内按倒序聚合展示所有关联练习的文字反思与录音标记，严格保持练习记录为单一真理源，修改统一跳转至原练习详情。

---

## User Stories

1. As a 吉他自学用户, I want 在项目详情页直观看到我的练习演进历程, so that 我能清晰感知自己从分段摸索到完整演奏的成长。
2. As a 吉他自学用户, I want 项目演进基于定性动作而非百分比数字打分, so that 我不会因抽象的进度条产生心理焦虑和打卡负担。
3. As a 吉他自学用户, I want 里程碑明确提示“根据已记录的练习范围 · 非完成度评分”, so that 我明白系统尊重乐器练习的真实探索本质。
4. As a 吉他自学用户, I want 在项目详情首屏看到上次练习的核心信息, so that 我能迅速回忆起上一次练习的内容和体会。
5. As a 吉他自学用户, I want 在上次练习卡片中直接查看练习反思与心得, so that 我能明确当时的真实手感。
6. As a 吉他自学用户, I want 在上次练习卡片中直接播放录音波形, so that 我无需跳转二级页面就能重温自己的演奏声音。
7. As a 吉他自学用户, I want 音频播放时波形柱随播放进度高亮变化, so that 我能清晰获得视觉与听觉同步的反馈。
8. As a 吉他自学用户, I want 点击“与阶段版对照”直接进入录音对比页, so that 我能对比当期录音与之前的差距。
9. As a 吉他自学用户, I want 录音对比页默认将我的阶段版本与最新录音进行对比, so that 我不需要每次手动挑选音频文件。
10. As a 吉他自学用户, I want 在我尚未设置阶段版本时系统自动选取项目最早一条有效录音作为对比基准, so that 新建项目在第二次录音时就能立刻体验对比。
11. As a 吉他自学用户, I want 在录音对比页点击“更换录音”, so that 我可以自由挑选任意两次历史录音进行定制对比。
12. As a 吉他自学用户, I want 在对比页看到“两次均为同一片段”的明确范围提示, so that 我确信对比是在相同维度下进行的。
13. As a 吉他自学用户, I want 阶段版和最近录音拥有独立的播放控制与波形进度, so that 我可以分别试听每一段。
14. As a 吉他自学用户, I want 点击“交替听 A / B”时播放能瞬间在两者之间切换, so that 我可以在耳朵记忆尚未消退时捕捉音色和节奏的细微变化。
15. As a 吉他自学用户, I want 播放任一音频时自动暂停另一个音频, so that 两个声音不会混在一起干扰辨别。
16. As a 吉他自学用户, I want 在对比页看到基于两段录音的定性 AI 观察与结论, so that 我能获得第三方客观维度的连贯度评价。
17. As a 吉他自学用户, I want 在 AI 观察中看到具体时间戳的对比证据（如 00:42 vs 00:38）, so that 我能精准定位到和弦转换或收尾卡顿的具体小节。
18. As a 吉他自学用户, I want 点击时间戳证据直接定位并试听该片段, so that 我无需手动拖动滑块寻找卡顿点。
19. As a 吉他自学用户, I want 录音对比页关联展示当时写下的练习笔记, so that 我能结合当时的主观感受理解现在的声音变化。
20. As a 吉他自学用户, I want 在断网或离线状态下录音对比页依然完全可用, so that 地下室或飞行模式下的练习不受网络阻碍。
21. As a 吉他自学用户, I want 在离线状态下 AI 观察卡片平滑展示基于笔记的结构化比对, so that 页面不会出现突兀的报错或空白。
22. As a 吉他自学用户, I want 在录音对比页底部点击“继续这次练习”, so that 我能立刻带着对比得出的弱点投入今日练习。
23. As a 吉他自学用户, I want 在项目详情页看到明确的“下次练什么”卡片, so that 我清楚今天练琴的核心抓手。
24. As a 吉他自学用户, I want “下次练什么”包含具体目标与操作说明, so that 我不需要在脑海中重新设计练习步骤。
25. As a 吉他自学用户, I want 点击“下次练什么”右侧提示能快速编辑修改重点, so that 当我的进度发生变化时能及时更新聚焦目标。
26. As a 吉他自学用户, I want 当天尚未开练时点击行动按钮直接创建今日首条练习, so that 我能一键进入练习工作台。
27. As a 吉他自学用户, I want 自动创建的今日练习预填项目重点并建立关联, so that 我无需重复手动输入练习名称。
28. As a 吉他自学用户, I want 当天已有未完成练习时点击行动按钮直接复用该条记录, so that 系统不会因为多次点击生成一堆 0 分钟空白垃圾数据。
29. As a 吉他自学用户, I want 当天已完成练习时点击行动按钮提示并开启第 2 趟练习, so that 我在一天内多次练习时记录清晰独立。
30. As a 吉他自学用户, I want 在项目详情页预览最近 3 条练习笔记, so that 我能快速扫览近期的心得体会。
31. As a 吉他自学用户, I want 点击单条笔记预览直接跳转到原练习记录详情, so that 我能查看当时包含计时与节拍器的全部现场。
32. As a 吉他自学用户, I want 点击“查看全部”进入项目的完整笔记历史列表, so that 我能按时间倒序系统阅读该项目的所有心路历程。
33. As a 吉他自学用户, I want 笔记列表中有录音的条目显式标注“有录音”角标, so that 我能快速筛选出带有音频成果的关键记录。
34. As a 吉他自学用户, I want 笔记列表底部明确说明“笔记来自每次练习，可在原练习记录中修改”, so that 我清楚数据维护的规则，不在项目层产生编辑冲突。
35. As a 吉他自学用户, I want 在一个没有任何练习记录的新项目里看到温暖的空状态引导, so that 我知道完成第 1 次练习就能点亮这些反馈。
36. As a 吉他自学用户, I want 当仅有 1 条录音时对比入口友好提示“再记录一次即可开启对照”, so that 我理解功能解锁的自然条件。
37. As a 吉他自学用户, I want 即使练习没有录音只记录了文字，项目详情仍能正常展示反思与时长, so that 纯文字用户体验同样完整。
38. As a 产品维护者, I want 笔记严格保持单一真理源, so that 不会在项目模型和练习模型间出现双向写冲突或脏数据。

---

## Implementation Decisions

### 1. 架构模块与职责边界

- **Project Detail 页面结构调整**：
  全面重构现有项目详情视图，移除原有的阶段槽位占位符、类型与完成度配置区；改为严格由以下四大组件构成的单向信息流：
  1. `ProjectProgressStoryView`：里程碑轴线组件，呈现阶段演进；
  2. `LastPracticeEvidenceCard`：上次练习证据卡，内嵌音频播放与对比跳转；
  3. `NextPracticeFocusCard`：聚焦重点行动卡，承接当前目标与状态机开练；
  4. `ProjectNotePreviewSection`：前 3 条笔记预览与查看全部入口。

- **新增独立界面**：
  1. `AudioComparisonView`：录音对比独立页，承载双轨波形播放器、A/B 切换、AI 停顿观察与关联笔记；
  2. `ProjectNotesListView`：项目笔记历史页，承载基于时间倒序的项目笔记只读投影流。

### 2. 状态机规范：Project Practice State Handoff

行动按钮触发逻辑统一收敛为领域纯函数，根据当前项目、当前时间与今日练习快照输出状态决策：

```
StateHandoffDecision:
  - todayNotStarted:
      action: createTodayPractice(title: project.currentFocus ?? project.name, projectId: project.id)
      buttonText: "开始今天的练习"
  - todayCreatedInProgress(existingItem):
      action: resumePractice(existingItem.id)
      buttonText: "继续这次练习"
  - todayCompleted(lastCompletedItem):
      action: promptAndCreateAnother(title: project.currentFocus ?? project.name, projectId: project.id)
      buttonText: "再练一次"
      evidenceRefresh: updates LastPracticeEvidence to lastCompletedItem
```

### 3. 里程碑提取启发式规则 (Progress Story Heuristics)

- 里程碑按定性范围划分，提取 1~3 个节点：
  - 范围 1（分段）：关键词匹配「分段 / 小节 / 副歌专项 / 慢练 / 和弦转换」；
  - 范围 2（连贯）：关键词匹配「串联 / 连贯 / 提速 / 爬格子」；
  - 范围 3（完整）：关键词匹配「完整 / 整首 / 跟唱摸底 / 录音对比 / 弹唱」。
- 节点标题优先提取练习条目标题核心短语，副标展示练习日期；
- 禁止向用户界面输出任何百分比进度条或打分数值，文案固定渲染：「根据已记录的练习范围 · 非完成度评分」。

### 4. 音频对比基准 (Audio Benchmark Version) 决策

- **基准 A 判定优先级**：
  1. 用户显式指定的阶段版本（`Project.milestoneVersionItemId`）；
  2. 若未指定，自动 fallback 选取该项目按 `createdAt` 升序排序的**第一条**有效录音；
- **对比方 B 判定优先级**：
  - 选取该项目除 A 之外按 `createdAt` 降序排序的**最新一条**有效录音；
- **版本更换**：
  - 用户在 `AudioComparisonView` 点击更换录音时，通过 Half-Sheet 选择其他录音临时覆盖 A 或 B，不强制修改持久化设置。

### 5. A/B 播放控制与互斥协议

- 页面内由独立的播放协调器控制，保证同一时刻仅有一个音轨处于播放状态；
- 点击「⇄ 交替听 A / B」时，执行原子操作：暂停当前播放轨道并记录进度，立即从该进度启动对侧轨道播放；若对侧音频时长较短，则从对侧对应百分比位置或起始点播放；
- 离开页面或进入系统后台时，试听播放器立即停止，释放系统音频资源，不干扰可能在后台运行的节拍器音频。

### 6. AI 听觉观察 (AI Audio Observation) 端侧降级契约

- 优先根据录音的时长、波形能量包络特征以及两次练习填写的 `note` 关键词进行结构化对比；
- 若云端分析可用且网络在线，异步填充时间戳与差异断言；
- 若离线或未接入网络，自动渲染本地轻量规则比对（提取两次笔记中的手感对比，如“停顿”与“连贯”），时间戳跳转功能降级为分段波形预览，保证 100% 离线高可用。

### 7. 数据与只读投影架构 (Single Source of Truth)

- 不新增独立的“项目笔记实体”表；
- `ProjectNoteProjection` 通过查询所有 `projectId == currentProjectId && deletedAt == nil` 且 `note != ""` 的 `PracticeItem` 动态投影生成；
- 点击列表条目或其跳转链接，统一通过 AppRouter 导航至对应的 `PracticeDetailView` 原始页面，由原页面执行修改和持久化。

---

## Testing Decisions

### 测试准则
- 坚持**最高可用缝（Highest Available Seam）**测试原则：测试外部用户行为与领域决策输入输出，绝不锁定内部 UI 视图私有变量或私有 Helper；
- 关注极端边界（0 练习冷启动、仅 1 条练习、有练习无录音、有录音无笔记、离线环境、跨天状态转换）；
- 所有业务推导规则（State Handoff、里程碑提取、基准版本裁决、笔记投影）全部以纯函数方式通过测试套件覆盖。

### 核心测试缝与模块

1. **`ProjectRulesTests`（领域规则最高缝）**：
   - 验证 `ProjectPracticeStateHandoff` 在“今天尚未开始”、“今天已创建未完成”、“今天已完成”三种状态下的行为决策；
   - 验证 `ProjectProgressStory` 在 0 条、1 条、多条练习下的里程碑提取正确性，验证无百分比数值产生；
   - 验证 `AudioBenchmarkVersion` 在显式设定阶段版、未设定 fallback 到首条有效录音、以及录音不足时的回退行为；
   - 验证 `ProjectNoteProjection` 的倒序排序、录音标记与空笔记过滤。

2. **`PracticeStoreTests`（数据流与持久化缝）**：
   - 验证从项目详情发起“开始今天的练习”时，新生成的 `PracticeItem` 正确绑定 `projectId` 且预填重点；
   - 验证在今日已有未完成练习时发起练习，Store 返回已有记录 ID，未新增垃圾数据；
   - 验证修改原练习的 `note` 后，重新加载项目详情及笔记历史，投影内容实时反映最新修改。

3. **`RecordPlaybackTests`（音频试听与 A/B 切换缝）**：
   - 验证 A/B 播放协调器互斥状态转换：播放 B 时 A 必须暂停；
   - 验证交替听（Toggle A/B）的时间点传递与无缝切换。

### 既有测试先例 (Prior Art)
- `ProjectRulesTests.swift`：既有项目列表分组、置顶、当前项目提取测试；
- `PracticeRecordRulesTests.swift`：既有练习记录有效性与过滤规则测试；
- `PracticeHomeStateTests.swift`：既有日级状态机与练习项复用测试。

---

## Out of Scope

1. **自动生成乐理评测报告或五线谱对齐**：本期不引入音频实时音高识别（Pitch Detection）或生成打分谱面。
2. **多项目关联单条练习**：一条练习记录依然严格归属于单个项目或独立练习。
3. **在项目详情页直接修改原练习笔记正文**：严格保持单向投影，修改必须跳转至原练习详情。
4. **引入破坏性 SwiftData Schema 迁移**：所有新状态与属性均在原有数据表和扩展属性上兼容演进。
5. **在没有录音的情况下伪造音频波形**：无录音时平滑隐藏播放条与对比入口，绝不展示虚假波形。

---

## Further Notes

- 本规格书完全替代原有的“项目详情三个探索方向”草案，将 Frame `1983:2` 明确固化为正式生产依据。
- 在后续开发落地过程中，UI 组件需遵循现有 `GitaTheme` 与 `GitaFont` 规范，所有文案保持对齐。
