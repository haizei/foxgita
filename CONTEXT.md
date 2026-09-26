# foxgita

Gita 吉他练习 iOS 应用。用户在日常练习中配置节拍器、计时、录音/录像，并记录练习步骤。

## Language

### AI 能力

**AI Recipe**:
一个用户可触发的、具有固定输入范围、Artifact 类型与批准策略的 AI 业务能力；当前共有下一次练习、图片计划、媒体复盘和视频诊断四种。
_Avoid_: AI 接口、AI Client、模型功能

**图片计划 Recipe**:
用户通过现场拍照或相册选择一至三张图片，生成可编辑 Practice Draft 的 AI Recipe；两个入口共享同一图片处理与生成边界。
_Avoid_: 拍照 AI、图片训练计划、自动建练习

**会话级派生图片**:
图片计划 Recipe 在当前生成会话内由用户所选原图生成的压缩视觉输入；可以在同一预览页重用，但不会成为长期业务数据。
_Avoid_: 缓存照片、上传原图、练习附件

**AI Artifact**:
模型输出经结构和领域规则校验后形成的不可变候选结果，尚不等于已经写入的业务对象。
_Avoid_: 模型响应、JSON 结果、最终数据

**Practice Draft**:
由下一次练习或图片计划 Recipe 生成、允许用户编辑且尚未加入今日练习的计划草稿。
_Avoid_: AI 练习、自动创建任务

**Review Result**:
针对既有录音或视频生成的派生分析结果；校验通过后可自动关联到原 Recording，但不等同于长期用户画像。
_Avoid_: Candidate Memory、用户能力结论

**Invocation Outcome**:
AI Invocation 经过 Artifact 展示后产生的业务采用结果，包括 accepted、abandoned、regenerated 或 failed。
_Avoid_: 请求状态、模型状态

**Candidate Memory**:
从 Review Result 提炼、拟进入用户长期画像但尚未获得用户批准的信息。
_Avoid_: Review Result、自动记忆、用户画像

**Host Approval**:
用户在预览界面针对特定草稿或 Candidate Memory 作出的明确批准；聊天文字不构成 Host Approval。
_Avoid_: 默认同意、生成即批准、聊天确认

**Recipe Migration State**:
单个 AI Recipe 的迁移生命周期：legacy、internalPlatform、platformDefault 或 removed。
_Avoid_: 新版 AI 开关、全局迁移状态

### 节拍器

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
