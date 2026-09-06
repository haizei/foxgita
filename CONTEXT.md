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
Display Card 中四根竖向动态柱，随当前拍高亮，表达强/弱/静音的重音模式。
_Avoid_: 四拍柱、beat bar（口语）

**Beat Track**:
Beat Bars 下方的胶囊形圆点轨，标记当前拍位置。
_Avoid_: 进度点、dot track

**Tempo Ruler**:
Speed Sheet 中的 BPM 滑杆（40–160），带刻度与拖拽 thumb。
_Avoid_: 速度滑块、slider

**Accent Pattern**:
每拍的重音状态：强拍 → 弱拍 → 静音，三态循环。
_Avoid_: accent、重音模式（作为泛称时）

## Decisions (2026-09-06, Metronome polish)

- **Sheet 架构**：Speed Sheet 独立；Meter + Subdivision 保持合并 Meter Sheet；Sound Sheet 已独立。
- **Display Card**：移除 tempo name，速度列只显示图标 + BPM（tempo name 仅在 Speed Sheet）。
- **验收标准**：像素级对齐 Figma `703:104`（含图标资产、spacing token）。
- **TAP 测速**：P1，本轮不做；Speed Sheet 先做 Ruler + ±。
- **Tempo Ruler 范围**：40–160（与 Figma 一致）；40–200 仍可通过 ± 到达。
- **弱拍色**：新增 `categoryOrangeSoft` token（#f5d2af），Beat Bar 专用。
- **图标资产**：从 Figma 导出 PNG/SVG 入 `Assets.xcassets`（速度图标、Sound 模式图标、Beat Track SVG）。
- **实现顺序**：1 tokens/资产 → 2 Display Card → 3 Speed Sheet → 4 Meter Sheet。
