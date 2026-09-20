# foxgita

Gita 吉他练习 iOS 应用。用户在日常练习中配置节拍器、计时、录音/录像，并记录练习步骤。

## Language

**Metronome Display Card**:
练习详情页内嵌的四列节拍器卡片（速度 / 拍号 / 音符 / 声音 + 四拍柱 + Beat Track）。
_Avoid_: 节拍器卡片、metronome card

**Speed Sheet**:
点击「速度」列弹出的独立底部面板，标题为「调整速度」，含 BPM 大字、± 步进、Tempo Ruler、TAP。
_Avoid_: 速度设置页、BPM sheet

**Meter Sheet**:
点击「拍号」或「音符」列弹出的底部面板，标题为「节拍器设置」，含节拍/拍号/音符三列控件、重音行、切分网格。
_Avoid_: 拍号设置页

**Sound Sheet**:
点击「声音」列弹出的底部面板，标题为「节拍提示」，含音色模式、音量、试听、强拍增强。
_Avoid_: 声音设置页、MetronomeSoundSheet（实现文件名可保留，但产品语言用 Sound Sheet）

**Beat Bars**:
Display Card 中随当前拍高亮的竖向反馈柱，表达 Accent Pattern。强、次强、普通以递增橙色强度显示，静音以一格中性灰标记显示；点击整根柱只改变对应拍，视觉立即更新，播放声音从下一 Bar Boundary 统一采用新序列。
_Avoid_: 四拍柱、beat bar（口语）

**Beat Track**:
Beat Bars 下方可点击的胶囊形节拍视觉反馈区；点击后在四种 Beat Track Mode 间循环切换。
_Avoid_: 进度点、dot track、装饰条

**Beat Track Mode**:
Beat Track 的视觉反馈策略，共有所有节拍、重音节拍、单摆、重音及次节拍四种；选择仅在当前练习期间保留。
_Avoid_: 灯效、动画样式、播放模式

**Main Beat Pulse**:
主拍到达时 Beat Track 的整条短时反馈；颜色跟随该拍的强、次强、普通或静音等级。
_Avoid_: 闪一下、主灯

**Secondary Pulse**:
一拍内部的次要支点，例如四个十六分音符中的第三下；力度低于 Main Beat Pulse、高于 Weak Subdivision Pulse。
_Avoid_: 次强拍、第二拍

**Weak Subdivision Pulse**:
一拍内部除 Secondary Pulse 外的轻拍；力度低于所属主拍，只在“重音及次节拍”模式中产生较窄、较浅的 Beat Track 反馈。
_Avoid_: 弱拍、普通拍

**Rest Position**:
节奏型中占据时间但不发声、不中断拍内推进的位置；它不产生 Beat Bars、Beat Track 或触觉反馈。
_Avoid_: 静音拍、跳过的拍

**Pendulum Feedback**:
“单摆”模式中随每个主拍在 Beat Track 两端交替移动的反馈；颜色跟随拍级，切分次拍不改变方向，停止后回到左端。
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

**Playback Continuity**:
Metronome Playback Run 在亮屏、锁屏和后台之间保持拍点与练习计时连续的产品承诺。
_Avoid_: 后台保活、锁屏不断音

**Recording Continuity**:
练习录音在自动熄屏、手动锁屏和进入后台后仍保持连续，直到用户停止或发生 Playback Interruption。
_Avoid_: 后台录音、锁屏录音模式

**Recording Segment**:
两次明确开始与结束之间连续采集的练习音频；Playback Interruption 会保存并结束当前片段，恢复后的录音属于新片段。
_Avoid_: 跨打断录音、临时录音文件

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
跨练习访问保留的拍号、细分、重音和声音选择；它独立于一次练习是否形成有效记录。
_Avoid_: Practice Session 配置、空练习记录

**Playback Diagnostic Event**:
用于重建播放生命周期的非内容事件，只包含时间、节拍配置、状态、错误码和设备路由类型，不包含练习内容或用户身份。
_Avoid_: 用户行为日志、逐拍日志

**Bar Boundary**:
由节拍器音频时间线定义的下一小节首拍，是 TAP 采用、变速阶段切换和 Pending Rhythm Change 的提交点。
_Avoid_: UI 小节边界、Timer 边界

**Target Hold**:
完成目标速度的完整阶段后，节拍器继续以目标 BPM 播放的训练状态。
_Avoid_: 训练已退出、普通播放
