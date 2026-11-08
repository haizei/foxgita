# 工具 Tab · 方案 A

用户已选择分组列表方案，并要求修改当前 Gita 代码。

设计来源：[Figma A · 分组列表](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd?node-id=2740-517)。

## 实现范围

- 在原生底部导航中新增「工具」，顺序为练习、记录、工具、设置。
- 工具页采用白色圆角列表，按「节奏与和弦 / 调音 / 听觉与演奏」分组，共七项。
- 复用 GitaTheme、GitaFont、系统状态栏、原生 TabView 和安全区。正文随 Dynamic Type 缩放，列表可滚动，整行均可点按。
- 节拍器打开独立页面，复用现有 Display Card、Speed Sheet、Meter Sheet、Sound Sheet 及音频引擎。其播放与设置不创建练习项、不累计练习时长、不写训练结果。
- 其他六项工具尚无实现，点击后明确提示「这项工具尚未开放，敬请期待。」。
- Sound Sheet 新增默认开启的 showsPracticeActions；只有独立工具隐藏练习录音和展开入口，原有练习页面保持既有行为。
- 离开独立节拍器或切换其他 Tab 时停止播放、清理临时速度与音频观察；系统中断和输出设备断开后不自动恢复。后台期间沿用音频引擎的连续播放规则，前台视觉反馈暂停。

## 资源与适配

从设计上下文下载九个 SVG：HomeTabTools、ToolMetronome、ToolChevron、ToolChords、ToolAlternateTuning、ToolChromaticTuner、ToolPlayAlong、ToolPlayChords、ToolChordMemory。均保存于本地 Asset Catalog 并保留矢量，运行时无临时 Figma URL。

图标尺寸为 24×24，箭头为 16×16，图标底色块为 38×38。新增 CategoryGreenSoft `#AFE2BC`、CategoryBlueSoft `#B7D5F4` 和 CategoryPinkSoft `#F7C3CF`，沿用现有橙、黄、紫分类色。系统栏与字体按现有原生应用适配，不模拟截图中的状态栏数据。

## 验证记录

- 新 UI 测试先在旧版应用运行，因缺少「工具」Tab 而失败。
- 新独立节拍器单元测试先在未实现模型时编译失败。
- 已检查九个 SVG 文件非空，manifest 指向有效本地文件，根尺寸与设计一致。
- 最终模拟器构建与定点回归通过：50 项单元测试、5 项 UI 测试，55 通过、0 失败、0 跳过。涵盖四个 Tab 的切换、七项入口、未开放提示、节拍器播放和设置、超大字号与深色模式。
- 现有音频引擎的连续播放稳定性用例在首轮运行通过，持续 180.902 秒。最终复验聚焦修改涉及的模型、导航、速度控制、显示卡与工具页，不把本轮结果描述为全项目测试通过。
- 独立 Swift 审查发现两处待切换速度残留：离开/中断的清理路径，以及暂停时下个小节回调被取消。补充用例先复现失败，修复后全部通过。用户已采用的 TAP 速度在停止状态即时落实，声音、BPM 显示与待切换提示保持一致；未修改原有练习节拍器引擎。
- 已检查浅色、深色与超大字号模拟器截图；[浅色工具页](../qa/2026-10-31-tools-tab-screenshots/tools-light.png)、[深色工具页](../qa/2026-10-31-tools-tab-screenshots/tools-dark.png)、[超大字号](../qa/2026-10-31-tools-tab-screenshots/tools-large-text.png)。
- [结构化验收结果](../qa/2026-10-31-tools-tab-results.json)。最终原始结果包：`/private/tmp/gita-tools-accepted.xcresult`。

没有提交、推送或发布。
