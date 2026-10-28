# foxgita

Gita 吉他练习 iOS 应用。用户在日常练习中配置节拍器、计时、录音/录像，并记录练习步骤。

## Language

**Metronome Display Card**:
练习详情页内嵌的节拍器卡片，展示拍号、速度、细分、Beat Bars 和 Beat Track，并提供音效与视觉设置入口。
_Avoid_: 节拍器卡片、metronome card

**Speed Sheet**:
点击「速度」列弹出的独立底部面板，标题为「调整速度」，含 BPM 大字、± 步进、Tempo Ruler、TAP。
_Avoid_: 速度设置页、BPM sheet

**Meter Sheet**:
点击「拍号」或「音符」列弹出的底部面板，标题为「节拍器设置」，含节拍/拍号/音符三列控件、重音行、切分网格。
_Avoid_: 拍号设置页

**Sound Sheet**:
承载音效、七种 Metronome Sound Preset 与视觉显示偏好的设置面板；更多声音设置承接强拍增强及独立的振动、闪拍提示。
_Avoid_: 声音设置页、MetronomeSoundSheet（实现文件名可保留，但产品语言用 Sound Sheet）

**Metronome Sound Preset**:
用户明确选择并保存的一种节拍声音，共有真实节拍器、电子节拍器、风铃声、木鱼声、架子鼓1、架子鼓2、拍手七种。
_Avoid_: Beat Cue Mode、声音模式、标准/穿透/高噪声模式

**Strong-Beat Sound Variant**:
与普通拍属于同一 Metronome Sound Preset、但让第一强拍在音色与响度上清楚可辨的声音变体。
_Avoid_: boost sample、简单放大、第二种声音预设

**Cross-Preset Loudness Consistency**:
相同音量与拍级下切换 Metronome Sound Preset 时，感知响度保持在可接受的小范围内。
_Avoid_: peak matching、全部一样响、自动音量

**Beat Bars**:
Display Card 中随当前拍高亮的竖向反馈柱，表达 Accent Pattern。强、次强、普通以递增橙色强度显示，静音以一格中性灰标记显示；点击整根柱只改变对应拍，视觉立即更新，播放声音从下一 Bar Boundary 统一采用新序列。
_Avoid_: 四拍柱、beat bar（口语）

**Beat Track**:
Beat Bars 下方承载节拍高亮和钟摆运动的前台视觉反馈区域；其显示由 Metronome Visual Preferences 控制，不改变真实发声序列。
_Avoid_: 进度点、dot track、装饰条

**Metronome Visual Preferences**:
所有练习共用的节拍器显示偏好，包含可同时开启的节拍模块与钟摆模式、Beat Highlight Filter 及小节计数显示选择；它与每条练习的声音和节奏配置分别保存。
_Avoid_: Beat Track Mode、灯效、播放模式、声音配置

**Beat Highlight Filter**:
用户选择强拍、次强拍和普通拍中哪些等级产生视觉高亮的显示偏好；取消某等级的高亮不改变该拍的发声、力度或节奏位置。
_Avoid_: Accent Pattern、静音设置、声音强拍增强

**Main Beat Pulse**:
主拍到达时 Beat Track 的整条短时反馈；颜色跟随该拍的强、次强、普通或静音等级。
_Avoid_: 闪一下、主灯

**Secondary Pulse**:
一拍内部的次要支点，例如四个十六分音符中的第三下；力度低于 Main Beat Pulse、高于 Weak Subdivision Pulse。
_Avoid_: 次强拍、第二拍

**Weak Subdivision Pulse**:
一拍内部除 Secondary Pulse 外的轻拍；力度低于所属主拍，在视觉反馈中以较窄、较浅的节拍提示表达。
_Avoid_: 弱拍、普通拍

**Rest Position**:
节奏型中占据时间但不发声、不中断拍内推进的位置；它不产生 Beat Bars、Beat Track 或触觉反馈。
_Avoid_: 静音拍、跳过的拍

**Pendulum Feedback**:
钟摆模式中随每个主拍在 Beat Track 两端交替移动的反馈，可与节拍模块同时显示；颜色跟随拍级，切分次拍不改变方向，停止后回到左端。
_Avoid_: 滑块、进度指示器

**Tempo Ruler**:
Speed Sheet 中按 Figma 显示并直接拖动 40–160 BPM 的刻度滑杆；节拍器整体仍支持 40–200 BPM。
_Avoid_: 速度滑块、slider

**Accent Pattern**:
每拍的重音状态；Meter Sheet 音符与 Beat Bars 统一按强 → 次强 → 普通 → 静音 → 强单向循环。
_Avoid_: accent、重音模式（作为泛称时）

**Tap Tempo Attempt**:
从第一次有效 TAP 到采用、取消、重置或中断的一轮临时测速采样；它不是持久化练习会话。
_Avoid_: TapTempoSession、TAP 会话

**Tempo Ramp Settings**:
Speed Sheet 的 B Segmented 扩展状态，编辑起始速度、目标速度、升速步长、触发小节和预备小节。
_Avoid_: 变速页面、第二个 bottom sheet

**Tempo Ramp Plan**:
一次变速训练采用的速度参数与拍号、切分、重音快照；训练开始后不可变。
_Avoid_: 变速配置、Ramp 模板

**Tempo Ramp Run**:
Tempo Ramp Plan 开始后的内存运行过程，包含阶段、小节进度、暂停与中断状态。
_Avoid_: TempoRampRuntime、变速 Session

**Metronome Training Session**:
一次已经开始的节拍器专项训练结果，记录完成原因、最高稳定 BPM 和暂停/中断次数。
_Avoid_: PracticeSession、TempoRampRuntime

**Metronome Playback Run**:
从用户开始播放到明确暂停或停止之间的一次连续节拍过程；自动熄屏、手动锁屏和进入后台不会自行结束它。
_Avoid_: Playback Session、后台任务

**Practice Elapsed Time**:
一次练习中实际发生并可保存的累计练习时长；它可在不启用节拍器时独立累计，录音与录像也属于练习。暂停与停止期间不增加，且不因倒计时的显示或复位而减少。
_Avoid_: 倒计时、剩余时间、目标时长

**Countdown Plan**:
用户为当前练习选择的 1–60 分钟倒计时总时长与结束提醒偏好；首次取当前练习目标时长，无目标时为 10 分钟，调整后从新总时长开始并等待用户再次启动。
_Avoid_: 目标练习时长、Practice Elapsed Time、倒计时模板

**Countdown Mode**:
练习计时卡以 Countdown Run 的剩余时间作为主显示的临时模式；关闭该模式会暂停播放、取消提醒，并恢复显示 Practice Elapsed Time，且该模式与 Tempo Ramp Run 互斥。
_Avoid_: 倒计时页面、倒计时 Tab、覆盖练习计时

**Countdown Run**:
Countdown Plan 启动后的当前练习内运行过程；它跟随 Practice Elapsed Time 开始、暂停和继续，不要求节拍器发声，在主动离开练习时结束，在锁屏或后台期间保持连续，发生播放打断后必须由用户明确恢复。
_Avoid_: Practice Session、PracticeTimer、后台任务

**Countdown Completion**:
Countdown Run 首次到达零点的单次完成事件；它停止节拍器、暂停 Practice Elapsed Time、保存并结束当前 Recording Segment，并按 Countdown Plan 触发结束提醒，但不等同于完成本次练习。
_Avoid_: 完成本次练习、自动保存、循环倒计时

**Countdown Reminder**:
用户明确启用的 Countdown Completion 反馈，前台包含提示音与成功触感，锁屏或后台包含一次本地通知；通知权限不可用时回退为关闭，但不阻止 Countdown Run。
_Avoid_: 每日提醒、自动完成通知、强制提醒

**Countdown Reset**:
将当前倒计时恢复到 Countdown Plan 的总时长并保持暂停；它不清零 Practice Elapsed Time，也不回滚笔记、步骤或节拍器配置。
_Avoid_: 重置整趟练习、清空练习、重新开始练习

**Playback Continuity**:
Metronome Playback Run 在亮屏、锁屏和后台之间保持拍点与练习计时连续的产品承诺。
_Avoid_: 后台保活、锁屏不断音

**Recording Continuity**:
练习录音在自动熄屏、手动锁屏和进入后台后仍保持连续，直到用户停止或发生 Playback Interruption。
_Avoid_: 后台录音、锁屏录音模式

**Recording Segment**:
一次开始录音至停止保存之间归属同一份附件的练习音频，可在同一片段内暂停和继续。主练习暂停同时暂停录音，录音自身暂停只影响采集；停止录音保存附件但不结束练习。Playback Interruption 会保存并结束当前片段，恢复后的录音属于新片段。
_Avoid_: 跨打断录音、临时录音文件

**Beat Unit**:
当前拍号分母代表的计拍音符，BPM 表示每分钟发生的这类拍点数；例如 6/8 的 120 BPM 表示每秒两个八分音符，不自动按附点四分音符换算。
_Avoid_: 固定四分音符速度、自动复合拍换算

**Bar Counter**:
沿真实节拍器播放累计的正式小节序号，第一小节为 1，预备小节不计入；暂停后继续保留计数，重置或新一轮播放重新起算。计数是否显示不影响声音与计时。
_Avoid_: 累计练习分钟、预备拍数、变速阶段数

**Playback Interruption**:
来电、Siri 或独占音频等系统事件强制结束当前连续播放的状态；事件结束后必须由用户明确恢复。
_Avoid_: 临时卡顿、自动续播

**Audio Service Reset**:
系统使当前音频引擎失效、无法继续保证原有拍点的事件；它同时暂停节拍器和练习计时，并等待用户明确恢复。
_Avoid_: 自动重连、普通音频打断

**Output Route Loss**:
当前耳机或音箱离开音频输出路径的事件；它会安全暂停播放，禁止无提示地切换到手机扬声器。
_Avoid_: 蓝牙断开、自动外放

**Foreground Beat Feedback**:
仅在应用位于前台时呈现的 Beat Bars、Beat Track 和强拍触觉反馈；锁屏或后台时，音频与练习计时继续，但此反馈暂停。
_Avoid_: 后台动画、锁屏震动

**Current Rhythm Configuration**:
当前实际控制小节结构、声音和 Foreground Beat Feedback 的拍号、细分与重音原子配置。
_Avoid_: 当前按钮、当前细分

**Configured Rhythm Configuration**:
用户最后选择、用于下一次开始播放的拍号、细分与重音原子配置；没有待提交变化时，它与 Current Rhythm Configuration 相同。
_Avoid_: 默认节奏、保存值

**Pending Rhythm Change**:
播放中最后一次请求、尚未到 Bar Boundary 生效的完整节奏配置；新请求整体替换旧请求，停止或打断前仍未提交时则成为 Configured Rhythm Configuration。
_Avoid_: 立即切换、局部待办、待切细分

**Playback Reliability Baseline**:
Metronome Playback Run 必须通过的两小时稳定性承诺，覆盖锁屏、音频边界和高负载配置变化，且不得崩溃、漏拍、重复拍或持续增长内存。
_Avoid_: 冒烟测试、听起来正常

**Saved Metronome Configuration**:
每条练习分别保留的速度、拍号、细分、重音和声音参数；它独立于练习是否完成，不因关联同一项目而自动共享，也不继承步骤级配置。
_Avoid_: 项目默认配置、步骤覆盖、Practice Session 配置、空练习记录

**Practice Note**:
每条练习记录唯一的一份可编辑文本笔记；自动保存只保留内容，不表示完成练习，项目中的笔记列表仍从原练习投影读取。
_Avoid_: 多条笔记条目、独立项目笔记、完成标记

**Practice Completion**:
用户明确结束本次练习的动作；详情页顶部与底部的完成入口表达同一含义，自动保存、返回和 Countdown Completion 都不等同此动作。
_Avoid_: 返回、自动保存、倒计时结束

**Temporary Metronome Mute**:
临时关闭节拍器发声但保留原音量和节奏配置的状态；取消静音后恢复原音量，不以修改声音预设表达静音。
_Avoid_: 音量归零、暂停练习、静音拍

**Auxiliary Beat Cue**:
声音之外辅助感知节拍的振动或闪拍；两者由独立用户选择控制，不由任何声音预设自动开启。
_Avoid_: 拍手自动闪拍、自动增强、强制振动

**Playback Diagnostic Event**:
用于重建播放生命周期的非内容事件，只包含时间、节拍配置、状态、错误码和设备路由类型，不包含练习内容或用户身份。
_Avoid_: 用户行为日志、逐拍日志

**Bar Boundary**:
由节拍器音频时间线定义的下一小节首拍，是 TAP 采用、变速阶段切换和 Pending Rhythm Change 的提交点。
_Avoid_: UI 小节边界、Timer 边界

**Target Hold**:
完成目标速度的完整阶段后，节拍器继续以目标 BPM 播放的训练状态。
_Avoid_: 训练已退出、普通播放

**Current Project Card**:
记录页「项目」Tab 顶部的当前主项目卡片，呈现项目名称、阶段标签、目标、上次有效练习证据、本次/今天聚焦意图与主操作按钮（开始今天的练习 / 继续这次练习 / 再练一次），以及累计时长与轨迹入口。
_Avoid_: 项目卡片、当前项目、project card

**Project Practice State Handoff**:
从记录页项目入口流转到今日练习的三状态机模型：01 今天尚未开始（创建首条今日练习）、02 今日已创建（复用未完成练习）、03 今天已完成（更新上次证据并创建新条目），保障空练习不冒充上次且练习 ID 不滥建。
_Avoid_: 项目练习状态、创建练习按钮逻辑

**Project Other List**:
记录页「项目」Tab 当前项目下方「其他进行中」的项目列表，每行 60pt 高度，展示项目名称与本次重点或最近练习上下文，点击统一导航至项目详情。
_Avoid_: 其它项目、进行中项目列表

**Project Progress Story**:
项目详情页顶部的定性练习轨迹，节点可回到有效原练习。只有用户明确记录或确认练习范围时才能展示范围变化；否则仅原样呈现练习事实，不根据标题、笔记、时长或录音数量推断演奏进步。
_Avoid_: 阶段路线、学习路线、完成度评分、项目进度条

**Last Practice Evidence**:
项目详情中展示最近一次有效练习的证据卡片，包含练习内容、个人反思体验、音频波形播放以及进入录音对比的入口。
_Avoid_: 最近练习卡片、练习历史摘要、上次打卡

**Audio Comparison**:
在项目内对两条具体可播放录音进行 A/B 交替试听的独立界面。可引用两次原始练习笔记；同片段提示仅在用户确认两条媒体与片段后显示，真实跨次分析另行交付。
_Avoid_: 录音回听、音频对比页、版本对比、波形对比

**Audio Benchmark Version**:
在 Audio Comparison 中作为 A 侧的具体练习录音。阶段版本或最早可播放录音仅是自动候选，不等同用户确认；用户可更换到另一条具体 RecordingRef，失效媒体不能继续作为有效选择。
_Avoid_: 初始录音、基准音轨、标准版、底稿录音

**AI Audio Observation**:
专项 P2 的跨次音频分析结果；需用户主动触发并授权，且真实分析结果能定位到两条具体录音后才展示。原练习笔记始终标为用户笔记，不能充当 AI 听觉分析。
_Avoid_: AI 点评、智能评分、AI 诊断、演奏打分

**Next Practice Focus**:
项目详情中展示和编辑 Project.currentFocus 的卡片。进行中项目点击「开始这项练习」会在本地今天创建新 PracticeItem；记录页另有明确「继续这次练习」入口用于恢复原项。
项目详情的已采纳界面以「下次练什么」作为该卡片标题。
_Avoid_: 下步计划、练习目标、下一步

**Project Note Projection**:
在项目详情与笔记历史页中，从关联练习记录中按时间倒序投影聚合的只读笔记列表；单条笔记维护在练习记录单一真理源中。
_Avoid_: 项目笔记、专属笔记、独立备忘、项目日志

**笔记语音输入 (Note Dictation)**:
用户在写笔记时按住说话、松手结束或上滑取消，通过设备端识别将结果插入当前光标位置，并可继续编辑的输入方式；原始语音不作为练习媒体保留。开始时暂停节拍器与练习计时，结束后由用户手动恢复。
_Avoid_: 练习录音、语音附件、整篇笔记替换

**笔记图片 (Note Image)**:
用户从相册选择或现场拍摄、归属本次练习记录，并可在记录详情中回看的图片；一条记录最多三张，未完成离开时仍保留，单独存在也构成有效练习内容。历史练习中的图片只可查看，不可新增或删除。
_Avoid_: 图片转练习素材、练习项封面、项目图片


**练习偏好 (Practice Preferences)**:
经 Guitar DNA 八题提交后生效的音乐方向与时间预算。填写草稿不等于生效；后续提交只刷新推荐候选与待确认方案。
_Avoid_: 演奏能力评分、两套用户偏好

**练习方案 (Practice Routine)**:
用户明确保存、可连续执行的一组训练分段。未完善偏好时显示通用方案；新预览不覆盖当前方案。
_Avoid_: 今日清单、自动生效建议

**方案训练汇总 (Program Training Summary)**:
按入口保存执行快照并引用实际 PracticeItem 明细的复盘投影。时长来自明细区间，不是额外的 Session 计时事实；暂停跨天仍关联同次安排。
_Avoid_: 独立会话时长、第二份练习记录时长
