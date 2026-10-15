# 项目详情已采纳方案：三屏对齐与证据可信度规格

> 日期：2026-10-15
> 目标仓库：`haizei/foxgita`
> 已发布：[GitHub issue #57](https://github.com/haizei/foxgita/issues/57)，标签 `ready-for-agent`
> 视觉基准：[项目详情｜已采纳方案](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd/?node-id=624-405)，含项目详情 `1983:3`、录音对比 `1983:4`、我的笔记 `1983:5`
> 需求依据：记录 PRD、2026-10-15 项目详情 Figma 与实现差异及需求修改草案、练习档案与 AI 跨次对比 PRD；修订既有 [项目详情规格 #49](https://github.com/haizei/foxgita/issues/49) 中相冲突的验收口径

## Problem Statement

用户进入项目详情，期望先看到自己实际练过的内容和留下的声音，再决定下一次练什么。现有 iOS 页面虽然已有项目详情、Audio Comparison 和 Project Note Projection，信息层级、卡片样式及导航与已采纳 Figma 不一致。更严重的是，页面会从标题或笔记关键词推断“从分段到完整”的进步，自动选最早与最近录音后宣称“用户确认的同一片段”，并把笔记规则文案标成基于两段音频的 AI Audio Observation。这些结论超出当前记录能证明的范围。多录音练习项还不能稳定选择某一条具体录音。

## Solution

以已采纳三屏画板为视觉和交互基准，重排项目详情的 Project Progress Story、Last Practice Evidence、Next Practice Focus、Project Note Projection，并调整 Audio Comparison 的录音行、A/B 控件及笔记引用。页面只展示可追溯到有效 PracticeItem 和具体 RecordingRef 的事实；缺少范围确认、同片段确认、媒体文件或真实分析时，显示明确的降级状态。进行中项目的“开始这项练习”遵循记录 PRD P0-R6，创建本地今天的新 PracticeItem 并防止一次操作重复提交。已完成与归档项目以回顾和重新开启为主。画板中的曲目、日期、里程碑及 AI 文案仅是示例数据。

## User Stories

1. As a 吉他练习者, I want 在项目详情看到项目名称与自己填写的完成标准, so that 我能确认正在回看哪个长期目标。
2. As a 吉他练习者, I want 项目详情保留“练习、记录、设置”主导航并高亮记录, so that 我能直接切换主要页面。
3. As a 吉他练习者, I want 从详情进入 Audio Comparison 或笔记历史后看到独立页面, so that 我能专注于回听或阅读并正确返回项目。
4. As a 吉他练习者, I want 在详情首屏看到有来源的 Project Progress Story, so that 我能回忆各次练习实际覆盖了什么。
5. As a 吉他练习者, I want 每个里程碑显示日期和原练习入口, so that 我能核对系统展示的练习范围。
6. As a 吉他练习者, I want 未明确记录或确认练习范围时只看到中性练习轨迹, so that 标题关键词不会被当作演奏进步的证据。
7. As a 吉他练习者, I want 新项目先看到第一次练习引导而非空的进步卡, so that 页面只呈现已有的事实。
8. As a 吉他练习者, I want 进展区说明它不是完成度评分, so that 我不会把范围变化误读成水平分数。
9. As a 吉他练习者, I want 在 Last Practice Evidence 中看到最近有效练习的日期、内容和原笔记, so that 我能接续上次的真实体验。
10. As a 吉他练习者, I want 直接播放最近练习中可访问的录音, so that 我能先听再决定是否对比。
11. As a 吉他练习者, I want 只有一条录音或文件失效时看到准确提示, so that 我不会点到无法播放的按钮。
12. As a 吉他练习者, I want 从上次练习进入可用录音的 Audio Comparison, so that 我能手动听两次练习的差异。
13. As a 吉他练习者, I want 在 Audio Comparison 页头看到“录音对比”、项目及已知片段信息, so that 我知道比较对象和比较范围。
14. As a 吉他练习者, I want A、B 两侧显示录音来源练习、日期时间、时长与可用性, so that 我能识别每一条具体录音。
15. As a 吉他练习者, I want 在同一 PracticeItem 有多条录音时选择指定 RecordingRef, so that 更换录音后听到的就是所选文件。
16. As a 吉他练习者, I want 在更换任一侧录音后重新从该录音的起点试听, so that 旧文件的播放位置不会套用到新文件。
17. As a 吉他练习者, I want 两侧录音独立控制且 A/B 交替时互斥播放, so that 声音不会叠在一起。
18. As a 吉他练习者, I want 在两条可播放录音尚未确认同片段时仍可手动 A/B 试听, so that 我可以自行判断是否适合比较。
19. As a 吉他练习者, I want 只有明确确认具体两条录音和比较片段后才看到同片段提示, so that 页面不会代替我作出确认。
20. As a 吉他练习者, I want 更换、删除、移出项目或丢失录音文件后重新校验确认状态, so that 过期的比较关系不会继续生效。
21. As a 吉他练习者, I want 没有真实跨次音频分析时不看到伪装成 AI 听觉观察的文案, so that 我能分辨自己的笔记和机器分析。
22. As a 吉他练习者, I want 在比较页继续看到两次原始笔记并能回到原练习, so that 我能用自己的记录解释听到的差异。
23. As a 吉他练习者, I want 在 Next Practice Focus 中看到自己保存且可修改的当前重点, so that 下次练习从真实意图开始。
24. As a 吉他练习者, I want 没有当前重点时看到明确空态, so that 系统不会编造训练内容。
25. As a 吉他练习者, I want 点击“开始这项练习”后创建一条属于本地今天、关联当前项目的 PracticeItem, so that 新一次练习有独立记录。
26. As a 吉他练习者, I want 当前重点进入新练习的初始内容, so that 我无需重复输入。
27. As a 吉他练习者, I want 一次创建过程中的重复点击只产生一条练习项, so that 不会留下重复空记录。
28. As a 吉他练习者, I want 创建失败后仍留在当前项目并能重试, so that 我不会丢失上下文或得到半成品记录。
29. As a 吉他练习者, I want 昨天的 PracticeItem 在今天新建后保持不变, so that 历史时长、笔记与媒体仍可信。
30. As a 吉他练习者, I want 已完成或归档项目优先展示成果与重新开启操作, so that 页面不会继续催促我默认开练。
31. As a 吉他练习者, I want 在项目详情预览最多三条原始笔记, so that 我能快速回顾近期感受。
32. As a 吉他练习者, I want 在“我的笔记”看到本项目有效笔记总数和倒序列表, so that 我能按时间找回记录。
33. As a 吉他练习者, I want 笔记行按日期列、标题与原文列排列并有细分隔线, so that 长列表易于浏览。
34. As a 吉他练习者, I want 只有存在可访问录音的笔记显示录音标识, so that 标识代表实际可回听的媒体。
35. As a 吉他练习者, I want 点击“查看练习记录”回到原 PracticeItem, so that 我能在唯一的编辑位置修改笔记。
36. As a 吉他练习者, I want 删除或移出项目后笔记预览、列表和数量同步变化, so that 项目视图不会残留旧数据。
37. As a 使用大字体或小屏设备的练习者, I want 三屏内容和操作仍清晰可达, so that 画板布局在我的设备上也能使用。

## Implementation Decisions

- 保留 ADR-0009 的 Progress First 信息顺序、定性而非百分比评分、Project Note Projection 只读且以原 PracticeItem 为唯一来源。已采纳记录 PRD 对证据来源、P0-R6 创建语义和 P2 AI 边界作了后续细化；旧规格与 ADR 中相冲突的具体回退规则须随实施同步修订，不能把冲突文本继续当成验收依据。
- 项目详情遵循画板的信息层级：项目身份；浅橙色 Project Progress Story 与日期节点；卡外标题和日期加暖色描边的 Last Practice Evidence；卡外标题和编辑入口加紧凑浅橙 Next Practice Focus；无外层阴影卡的 Project Note Projection 预览。详情显示主导航，两个次级页面隐藏主导航。402 × 874 为视觉对照尺寸，布局须支持实际设备安全区、动态字体和长文案。
- Project Progress Story 只从用户明确记录或确认的练习范围构造范围节点。标题、笔记、时长和录音数量可以作为原样事实展示，不能单靠关键词推导“分段、连贯、完整”或演奏能力提升。范围证据不足时展示中性轨迹；无有效练习时不渲染空时间线。节点打开对应原 PracticeItem。
- Last Practice Evidence 按当前项目最新有效 PracticeItem 取值，保留其原笔记和具体可访问媒体。无媒体时保留文字证据但隐藏播放条；单条媒体或文件失效时提供准确状态。对比入口需有两条可播放的不同录音；未确认同片段也可以进入手动试听，但入口与页面都不得暗示已确认的演奏改善。
- Audio Comparison 的选择与播放身份由 PracticeItem.id 加 RecordingRef.id 共同确定，两个侧位各保存具体媒体选择；候选可以来自用户指定阶段版与近期录音，或最早与近期录音，但自动候选仅代表待确认的可播放对象，不代表用户已选定 Audio Benchmark Version 或同片段事实。同一侧换录音后清理该侧播放进度、暂停状态及依赖旧媒体的确认。
- “两次均为用户确认的同一片段”只能在用户显式确认两条具体录音及片段范围后出现，并保存可复查的两侧媒体身份与片段描述。来源变更、删除、移出项目或文件失效后，确认与依赖它的结论失效；两侧仍可播放时可回到未确认的手动 A/B 状态。未知片段显示未知，不用练习项标题冒充片段标签。
- 播放前验证两侧为可访问的音频文件。失效侧展示更换录音及返回原练习的路径，不显示可成功播放的假按钮。沿用现有互斥播放；交替按钮位于两条录音行之间。播放状态和波形进度须与实际文件对应。
- 本规格只交付手动 Audio Comparison 与原始笔记引用。AI Audio Observation 是专项 PRD 的 P2 条件模块：在用户主动触发并授权、真实跨次分析返回、且两侧证据可定位前，不显示“AI 基于两段录音”的观察、时间戳或演奏变化判断。离线、失败和取消不影响手动 A/B；笔记摘要必须标为用户原笔记。
- Next Practice Focus 的可编辑内容来自 Project.currentFocus；空值保留为空态。进行中项目从详情和比较页触发同一创建流程：按本地日期创建新 PracticeItem、关联 Project.id、用当前重点预填、进入练习页。一次提交须幂等；创建失败可重试。已存在今天的练习不应使一次新的明确点击静默恢复旧项；如另有“继续”入口，应使用对应文案并路由到原项。
- Project Note Projection 按有效、未删除、仍属于当前项目且原笔记非空的 PracticeItem 倒序投影。详情最多预览三条，历史页显示全部及同口径计数；音频标识按可访问的具体媒体判定。历史页保持只读，修改从原 PracticeItem 进行。
- 已完成项目优先显示用户指定的可访问最终版本及重新开启入口；归档项目提供回顾与重新开启入口。两者不显示默认“开始这项练习”催练操作。任何项目状态都不制造示例数据。

## Testing Decisions

- **主测试缝：三屏用户流程。**扩展现有轻量 UI 测试，从记录页进入项目详情、Audio Comparison 和“我的笔记”，验证导航、操作、空态及可见文案。用确定性练习与录音夹具覆盖多录音同练习项、两条待确认录音、缺失文件、已完成项目及大字体。截图对照 Figma 的 402 × 874 关键层级，并在小屏和长文案下检查内容可见与控件可点击；不锁定私有视图变量或单个像素。
- **沿用现有领域与数据缝：**项目规则测试验证有来源的里程碑、原练习跳转身份、笔记过滤和投影、具体录音选择及失效；存储测试验证创建今天的新 PracticeItem、同次重复提交、失败回退和原笔记修改后的刷新；播放测试验证所选媒体身份、换片进度重置与 A/B 互斥。测试对外可观察的结果，不测试内部 helper 的调用顺序。
- **先例：**现有 `PracticeFlowUITests` 覆盖记录 Tab 和 Figma 截图检查，`ProjectRulesTests` 覆盖项目、里程碑、候选与笔记投影，`PracticeStoreTests` 覆盖持久化，`RecordPlaybackTests` 覆盖 A/B 互斥。新增测试优先沿用这些入口，不为每个新视图另造测试接口。
- **关键验收数据：**零条有效练习；仅一条文字练习；两条仅标题含“分段/完整”但未确认范围的练习；同一 PracticeItem 的两条录音；两侧片段未确认与已确认；一侧媒体丢失；笔记修改、删除和移出项目；今天已有练习且再次明确开始；创建失败；完成及归档状态。以上状态不能出现伪进步、伪 AI、伪同片段或不可用播放按钮。

## Out of Scope

- 跨次 AI 音频分析、模型服务接入、AI 结果存储和质量评测；按专项 PRD P2 单独交付。
- 音高、节奏、完成度的自动评分，以及凭时长或波形估算技能提升。
- 在项目页面直接编辑原笔记，或建立独立项目笔记副本。
- 把画板示例曲目、日期、文字或波形写入真实用户数据。
- 多项目共用一条 PracticeItem；阶段任务体系或课程式百分比进度。

## Further Notes

- 本规格将已实现三屏与 Figma 的差异落实为后续修改要求，并修订既有“项目详情 · 先看见进步”规格中不可信的自动推断、自动确认及笔记伪 AI 口径；相关旧验收见 [#49](https://github.com/haizei/foxgita/issues/49)、[#54](https://github.com/haizei/foxgita/issues/54) 和 [#55](https://github.com/haizei/foxgita/issues/55)。ADR-0009 的总体架构保留；其自动 Audio Benchmark Version 回退、离线 AI 观察回退和恢复今日练习等细节须在实施时按本规格与较新的 PRD 更新。`CONTEXT.md` 中这些术语的旧定义也须同步校正，避免把候选误称为用户确认的基准。
- `PracticeItem` 在本规格中指某日一次实际练习记录；`RecordingRef` 指具体媒体。旧产品理念文档对“练习项”曾作可重复执行方法的定义，实施时使用记录 PRD 的当前语义，不新增同名领域对象。
- 视觉验收以已采纳画板的结构、颜色关系、信息层级和交互位置为准；示例内容随真实项目数据变化。已有的比较页和笔记页隐藏主导航、A/B 互斥、笔记源记录跳转等行为应保持。
