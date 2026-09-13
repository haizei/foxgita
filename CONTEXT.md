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
Display Card 中随当前拍高亮的竖向反馈柱，表达 Accent Pattern。强、次强、普通以递增橙色强度显示，静音以一格中性灰标记显示；落拍时柱内填充替换为高对比深暖棕色，边框始终保持中性。
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

**Subdivision Pulse**:
“重音及次节拍”模式中，切分次拍到达时 Beat Track 中央较窄、较浅的短时反馈；静音拍所属的次拍不产生反馈。
_Avoid_: 次强拍、弱拍闪烁

**Pendulum Feedback**:
“单摆”模式中随每个主拍在 Beat Track 两端交替移动的反馈；颜色跟随拍级，切分次拍不改变方向，停止后回到左端。
_Avoid_: 滑块、进度指示器

**Tempo Ruler**:
Speed Sheet 中按 Figma 显示并直接拖动 40–160 BPM 的刻度滑杆；节拍器整体仍支持 40–200 BPM。
_Avoid_: 速度滑块、slider

**Accent Pattern**:
每拍的重音状态；点击单拍音符时按静音 → 普通 → 次强 → 强 → 静音逐步递增循环。
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

**Bar Boundary**:
由节拍器音频时间线定义的下一小节首拍，是 TAP 采用和变速阶段切换的提交点。
_Avoid_: UI 小节边界、Timer 边界

**Target Hold**:
完成目标速度的完整阶段后，节拍器继续以目标 BPM 播放的训练状态。
_Avoid_: 训练已退出、普通播放

## Decisions (updated 2026-09-11, Metronome tempo training)

- **Sheet 架构**：Speed Sheet 独立；Meter + Subdivision 保持合并 Meter Sheet；Sound Sheet 已独立。
- **Display Card**：移除 tempo name 与速度图标，速度列只显示居中的 BPM（tempo name 仅在 Speed Sheet）。
- **验收标准**：像素级对齐 Figma `703:104`（含图标资产、spacing token）。
- **TAP 测速**：纳入 Speed Sheet；只保留一个 TAP 入口，结果需显式采用。
- **Tempo Ramp Settings**：使用 B Segmented 扩展状态，不叠加第二个 sheet。
- **Tempo Ruler 范围**：按 A Compact 显示并直接拖动 40–160；Engine、± 和 TAP 仍支持 40–200。
- **训练边界**：TAP 采用和变速阶段切换只在音频时间线的小节首拍提交。
- **训练持久化**：Schema V18 使用独立 TempoRampPlan 和 MetronomeTrainingSession；不复用 PracticeSession。
- **Beat Bars 色阶**：普通 `#FFCCA6`、次强 `#FF9961`、强 `#FF6B1A`、静音 `#BDC2C9`；连续填充格不显示内部缝隙。
- **Beat Track 交互**：点击按“所有节拍 → 重音节拍 → 单摆 → 重音及次节拍”循环；模式仅在当前练习内保留，静音拍在所有节拍与单摆模式中仍提供灰色视觉反馈。
- **图标资产**：从 Figma 导出 PNG/SVG 入 `Assets.xcassets`（速度图标、Sound 模式图标、Beat Track SVG）。
- **实现顺序**：1 tokens/资产 → 2 Display Card → 3 Speed Sheet → 4 Meter Sheet。
