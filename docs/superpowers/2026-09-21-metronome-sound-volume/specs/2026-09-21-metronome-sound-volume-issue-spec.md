# 节拍器声音库与音量修复 — Issue 规格

> 日期：2026-09-21
> 状态：`ready-for-agent`
> 目标仓库：`haizei/foxgita`
> 来源：已确认的声音选择、音量修复开发讨论与领域决策

## Problem Statement

用户在 App 内运行节拍器时，即使音量滑块已经较高，声音仍然偏小，尤其在手机外放和正常力度木吉他演奏时容易被掩蔽。现有实现用 30ms 单正弦波模拟“标准、穿透、高噪声”三种模式，峰值振幅虽然不低，但缺少足够的瞬态能量与泛音；低频模式在手机扬声器上的实际可辨认性尤其差。现有测试只验证音量数值范围，没有阻止“波形没有削波、听感却很小”的回归。

与此同时，产品设计已经从三个环境模式调整为七种明确的 Metronome Sound Preset。旧 UI、领域术语、持久化值与新设计不一致，用户也无法按照参考设计直接选择真实节拍器、电子节拍器、风铃声、木鱼声、架子鼓1、架子鼓2和拍手。

## Solution

将旧“标准 / 穿透 / 高噪声”模式替换为七种明确的 Metronome Sound Preset，并使用 App 内置、预加载、经过响度校准的普通拍/强拍 PCM 短采样取代运行时单正弦合成。Sound Sheet 使用三列网格展示七项，移除选项前置序号并排除所有中文或英文人声。

音量修复以可测量的素材合同和真机节拍可辨认性为准：相同拍级下七种声音的有效响度差不超过 2 dB，普通拍素材达到统一有效响度基线，Strong-Beat Sound Variant 比普通拍高 4–6 dB，所有组合在 100% 音量下保留至少 1 dB 峰值余量。默认 App 音量继续为 80，旧用户保存的音量不发生迁移跳变。

旧 raw value 在读取时安全映射到新预设，新写入只使用新 raw value；其他节拍、音量和练习数据不得丢失。与其他 App 音频继续直接混播，不自动压低伴奏；播放与录音共存状态的节拍器听感差控制在 2 dB 内。

## User Stories

1. As a 吉他练习用户, I want 在系统音量适中的情况下清楚听见节拍器, so that 我不需要把手机音量长期推到最大。
2. As a 吉他练习用户, I want 在正常力度弹木吉他时仍能辨认普通拍, so that 乐器声音不会持续掩蔽节拍。
3. As a 吉他练习用户, I want 清楚区分普通拍和强拍, so that 我能稳定感知小节起点。
4. As a 吉他练习用户, I want 从七种明确命名的声音中选择, so that 我能选到符合个人听感和练习环境的节拍声。
5. As a 吉他练习用户, I want 选择真实节拍器, so that 我能获得传统机械节拍器的听感。
6. As a 吉他练习用户, I want 选择电子节拍器, so that 我能获得短促清晰的电子节拍声。
7. As a 吉他练习用户, I want 选择风铃声, so that 我能获得更轻盈但仍可辨认的节拍声。
8. As a 吉他练习用户, I want 选择木鱼声, so that 我能使用具有清晰瞬态的木质节拍声。
9. As a 吉他练习用户, I want 在两套架子鼓声音之间选择, so that 我能匹配不同练习内容的律动感。
10. As a 吉他练习用户, I want 选择拍手声, so that 我能在合奏或较嘈杂环境中获得容易辨认的提示。
11. As a 吉他练习用户, I want 声音选项不带无意义的前置序号, so that 界面更简洁并与最终设计一致。
12. As a 吉他练习用户, I want 声音列表排除中文和英文人声, so that 我只看到本次产品范围内的七种节拍声。
13. As a 吉他练习用户, I want 切换声音时音量不会突然明显变大或变小, so that 我可以安全比较不同声音。
14. As a 吉他练习用户, I want 音量滑块继续显示并保存 0–100, so that 升级后我熟悉的控制方式不变。
15. As a 吉他练习用户, I want 0 音量产生可靠静音, so that 我可以保留时间线和视觉反馈而不发声。
16. As a 吉他练习用户, I want 100% 音量和强拍增强同时开启时没有爆音或削波, so that 高音量练习仍然安全清晰。
17. As a 吉他练习用户, I want 关闭强拍增强后仍保留拍级强弱顺序, so that Accent Pattern 的语义不会被破坏。
18. As a 吉他练习用户, I want 在节拍器播放中切换声音而不中断节拍, so that 我的练习时间线保持连续。
19. As a 吉他练习用户, I want 停止状态下试听当前声音和音量, so that 我可以在开始练习前完成选择。
20. As a 吉他练习用户, I want 试听失败时看到可以理解并重试的错误, so that 我不会把无声误认为按钮无效。
21. As a 使用旧版本升级的用户, I want 原来的声音配置自动映射到合理的新声音, so that 升级后不用重新设置。
22. As a 使用旧版本升级的用户, I want 已保存的音量、强拍增强、拍号、细分和 Accent Pattern 保持不变, so that 声音迁移不会破坏练习配置。
23. As a 使用伴奏练习的用户, I want App 不自动压低其他音频, so that 伴奏不会因节拍器启动而忽大忽小。
24. As a 录音练习用户, I want 开始录音时节拍器继续播放且听感基本不变, so that 我不需要在录音和节拍之间取舍。
25. As a 使用耳机或蓝牙设备的用户, I want 节拍器遵循当前系统输出路由, so that App 不会突然切回扬声器。
26. As a 使用辅助功能的用户, I want VoiceOver 按视觉顺序朗读声音名称和选择状态, so that 我可以独立完成声音选择。
27. As a 产品维护者, I want 七种声音拥有稳定 raw value 和固定显示顺序, so that UI、本地化、持久化和分析数据不会漂移。
28. As a 产品维护者, I want 每个发布音频素材都有合法来源和授权证明, so that 产品不会引入版权风险。
29. As a 音频开发者, I want 素材在集成前自动验证格式、时长、峰值和有效响度, so that 不合格素材不能再次造成声音过小或削波。
30. As a 开发者, I want 缺失非默认声音时安全回退到真实节拍器并记录诊断信息, so that 单个资源问题不会导致节拍器完全无声。
31. As a 开发者, I want 默认真实节拍器资源不可用时返回显式错误, so that 严重打包错误不会被静默掩盖。
32. As a QA, I want 在小尺寸和主流 iPhone 扬声器上执行统一真机矩阵, so that 验收反映真实设备而不只是模拟器波形。
33. As a QA, I want 验证 200 BPM 十六分音符的持续播放, so that 最短拍间隔下不会发生尾音挤压、漏拍或内存增长。
34. As a 未来维护者, I want 旧“标准 / 穿透 / 高噪声”只作为兼容输入存在, so that 新功能不会重新引入已经废止的环境模式概念。

## Implementation Decisions

- 产品领域统一使用 Metronome Sound Preset，固定为真实节拍器、电子节拍器、风铃声、木鱼声、架子鼓1、架子鼓2、拍手；显示顺序同时作为键盘导航和 VoiceOver 顺序。
- Sound Sheet 保留「节拍提示」标题，声音区使用「音效选择」；七项采用三列自适应网格，不显示选项前置序号。“架子鼓1 / 架子鼓2”中的数字属于正式名称。
- 不增加或隐藏人声枚举项；中文人声和英文人声均不属于本次数据模型。
- 每种声音由普通拍和 Strong-Beat Sound Variant 两个预加载 mono PCM 短采样组成，共 14 个发布资源。
- 素材统一为 44.1 kHz、16-bit、mono Linear PCM，开头静音不超过 1ms，总长不超过 70ms，结尾平滑淡出，true peak 不高于 -1 dBFS。
- 普通拍的 A 加权有效 RMS 目标为 -12 dBFS ±1 dB；同一拍级的七种声音之间最大响度差不超过 2 dB；同一预设的强拍比普通拍高 4–6 dB。
- 新的 Sound Bank 在首次播放前预加载并缓存全部资源，负责格式转换和显式错误；播放调度继续使用音频时间线的 sample time，不改用 UI Timer。
- 旧单正弦 recipe、频率、decay 和运行时 click 合成退出发布路径。资源失败不得静默回退到旧合成器。
- 拍级映射按 Strong、Medium、Weak、Secondary Subdivision、Weak Subdivision 依次衰减；Strong-Beat Sound Variant 只在强拍增强开启时用于 Strong main beat。
- 用户音量继续保存为整数 0–100，默认 80；0 为数字静音，100 为经过校准素材的 0 dB 用户增益。本次不改变既有线性振幅曲线。
- 音量、拍级增益和素材校准组合后的任何输出都必须保留至少 1 dB 峰值余量，不再使用截顶式 `1.4×` 强拍放大。
- 播放中切换声音不停止引擎、不重置 beat/bar index。已经进入约 100ms 调度窗口的 buffer 可以完成，变更后的第一个尚未调度可听拍点必须使用新声音。
- 试听继续使用当前声音、音量、强拍增强、BPM、拍号和细分快照；启动失败必须传播为可展示、可重试的错误。
- 保留现有 String 持久化列，避免为了字段改名修改已发布 SwiftData Schema；应用层将其解释为 sound preset raw value。
- 旧值映射为：`standard → realMetronome`；`penetrating/acousticGuitar → electronicMetronome`；`highNoise/drums → handClap`；nil 或未知值 → `realMetronome`。
- 成功保存后只写新 raw value。旧值解码不得重置音量、强拍增强或任何节奏与练习字段。
- 单独播放继续使用主动播放类别并与其他音频混播；录音共存继续使用录放类别、默认扬声器和混播。不得启用自动 ducking。
- 输出路由、中断和 Audio Service Reset 继续遵循 Playback Continuity：安全暂停并等待用户明确恢复。
- 每个音频资产必须记录来源、作者或供应商、授权类型、授权证明和编辑记录；授权不完整的资产不得进入发布构建。
- 非默认资源损坏时，发布构建回退到真实节拍器的相同拍级并记录不含用户内容的诊断事件；默认资源损坏时停止并返回明确错误。
- 产品决策由“以明确声音预设和预加载采样取代节拍提示模式”ADR 约束；音频实现由“使用预加载校准采样”ADR 约束。

## Testing Decisions

- 主要测试缝采用现有的 MetronomeEngine 公共配置与播放接口：从 Sound Sheet 产生的 preset/volume/boost 配置进入引擎，观察公开状态、时间线事件、播放连续性、持久化结果和可分析的输出 buffer。它是覆盖 UI 意图、领域模型和音频行为的最高现有缝，不为每个内部 helper 建立测试。
- 素材合同是唯一额外测试缝，因为 Bundle 中的静态音频在进入引擎前必须独立阻止版权外的技术缺陷。测试观察资源可打开性、格式、时长、静音、DC offset、true peak、A 加权有效 RMS、cross-preset spread 和 strong/beat difference，不锁定内部加载实现。
- 枚举与持久化测试覆盖七项固定顺序、精确显示名、稳定 raw value、新值 round-trip、所有旧值映射、nil/未知值回退，以及迁移不改变其他字段。
- 引擎行为测试覆盖 0/100 边界、数字静音、拍级响度单调递减、所有声音最大音量无 NaN/Inf/削波、播放中切换不重置时间线、试听自动停止、错误传播和 fallback。
- 集成测试通过现有 PracticeStore 边界验证 Saved Metronome Configuration 的保存、重新加载、可编辑练习和 Historical Practice 显式保存行为。
- Audio Session 测试延续现有 AudioSessionCoordinator 的依赖注入与引用计数先例，验证 playback/playAndRecord 选择、混播、不启用 ducking、失败回滚、中断和 route loss；不测试 Apple 框架内部实现。
- 压力测试以 200 BPM 十六分音符持续调度为外部行为，验证无漏拍、重拍、buffer underrun 或持续内存增长。
- 真机验收覆盖至少一台小尺寸扬声器 iPhone 和一台当前主流 iPhone；在系统音量 60%、App 音量 80%、设备距演奏者约 0.5m、正常力度木吉他场景下，七种普通拍均须持续可辨。
- 最大音量真机测试覆盖 App 与系统音量 100%、强拍增强开启，要求无数字削波、破音或不可接受的刺耳感。
- 混播、扬声器录音、耳机录音、有线耳机、蓝牙、拔出或断开路由分别验收；播放与录音共存状态的有效响度差不超过 2 dB。
- 至少 6 名目标用户执行同设备同音量对比，至少 5 人能够持续辨认七种声音的普通拍与强拍，且不得有超过 1 人报告某个预设明显过小或强拍爆音。
- 既有测试先例包括 MetronomeEngine 的音量边界、预览和播放中切换测试，MetronomeSoundMode 的稳定 raw/legacy decode 测试，MigrationTests 的跨 Schema 数据保留测试，以及 AudioSessionCoordinator 的录音优先、中断与 route/reset 测试。

## Out of Scope

- 中文或英文人声报拍、语音计数。
- 在线下载声音包、付费声音、用户导入声音。
- 环境麦克风监听、噪声识别或自动切换声音。
- 自动压低伴奏或其他 App 音频。
- 为单个预设隐藏修改用户音量滑块。
- 改变现有音量持久化范围或默认值。
- 仅调高振幅常量、仅将默认音量改为 100，或保留 30ms 单正弦作为发布方案。
- 对拍号、Subdivision、Accent Pattern、Beat Track 或 Tempo Ramp 进行产品改版。
- 为字段语义改名而修改任何已发布 VersionedSchema。
- 在本 Issue 中采购或创作最终音频素材；素材交付是实现前置条件，但必须符合本规格合同。

## Further Notes

- 当前仓库尚未包含最终 14 个音频素材；实现工作在素材授权与合同校验通过前不能视为发布就绪。
- 旧“三种节拍提示模式”产品 ADR 已被新声音预设 ADR 取代，旧文档仅用于解释历史实现与迁移。
- 发布门槛是用户在真实设备和吉他练习中的 Beat Audibility，不是单纯波形峰值或模拟器中“能发声”。
- UI、领域模型、引擎、迁移和 QA 必须共同使用 Metronome Sound Preset、Strong-Beat Sound Variant 与 Cross-Preset Loudness Consistency 术语。
