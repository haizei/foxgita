# 练习详情全流程改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按已确认的 Q1–Q13 将十个练习、节拍器与倒计时场景实现为可保存、可恢复的原生功能。

**Architecture:** PracticeDetailView 负责组合视图，新的 PracticeRuntimeCoordinator 协调现有计时、倒计时、节拍器、录音及录像；PracticeStore 继续承担唯一写入命令。新增视觉偏好和笔记保存器有独立边界，复用现有音频调度与媒体文件存储，不引入云端或替代数据库。

**Tech Stack:** SwiftUI、Observation、SwiftData V19、AVFoundation、UserDefaults、Swift Testing、XCTest UI；iOS 18+。

**Spec:** [2026-10-28-practice-ui-rebuild-design.md](../specs/2026-10-28-practice-ui-rebuild-design.md)。实施前同时阅读访谈及 ADR-0001–0008、0010–0012。

**PRD:** [2026-10-28-practice-ui-rebuild-prd.md](../specs/2026-10-28-practice-ui-rebuild-prd.md)。R01–R09 是产品验收分组；旧 #28/#31/#33/#34 的冲突规则已在 PRD 第 12 节说明，不能作为本轮隐含前置范围。

**Published Spec:** [Issue #59](https://github.com/haizei/foxgita/issues/59)，`ready-for-agent`；用户已明确确认以练习详情端到端流程为主测试边界。产品规则不需重复访谈，音色候选仍按既定内容评审步骤在产出后选择。

## 实施状态（2026-10-28）

- [x] 运行/计时/保存基础及本地故障恢复已实现，并按约定主流程验证。
- [x] 完整MT-04、调速、拍号单位、共享全屏、倒计时与笔记媒体入口已联通。
- [x] 音频排队后的下一拍换色、静音和硬截止补充实际PCM测试；候选已生成并复审。
- [x] 两轴代码审查及Python试听脚本审查，已发现问题均修复。
- [x] 完整套件已执行；旧入口断言修正后定点复验，独立副本回归与十场景截图已归档。
- [ ] 需求方选择候选后更新正式音色；尚未收到选择，正式素材保持原版。
- [ ] 真机矩阵及两小时稳定性验收；当前无已连接真机，不伪报通过。

具体命令、截图、工程调整及未测项见 [验证记录](../../qa/2026-10-28-practice-ui-rebuild-verification.md)。下面任务清单保留原设计的细项定义；完成状态以本节和验证记录为准。

## Global Constraints

- 技术基线：SwiftUI、Observation、SwiftData，最低 iOS 18；现有 schema V19。
- 后端指本地领域服务、文件、持久化和兼容逻辑，本轮不新增云服务。
- 保留当前工作区既有功能与未提交修改；不重置仓库，不将其他工作混入提交。
- PracticeItem 是单份笔记、累计时长、配置及媒体关系的事实来源；不增加步骤实体、项目配置继承或第二份练习时长。
- 沿用现有七种音色的稳定 rawValue、八种细分、四态重音、40–200 BPM、2–12 拍及变速训练能力。
- 不实现未定义的第二页细分、PDF/乐谱解析或新的 AI/同步功能。
- 白底完整 MT-04 来自主件 2646:1275 / 实例 2651:1380，不得回到旧紧凑音色列表。
- 保留系统字体、Dynamic Type、44pt 命中区和原生可访问状态。

## Review Focus

1. 主暂停与录音自身暂停交错，继续不能意外打开用户已经暂停的录音（Task 2）。
2. 相机/全屏/导入弹层触发 onDisappear，不能当成真实离开练习或重复累计时间（Task 2、5）。
3. 连续输入期间慢保存失败再返回，旧版本不能覆盖新笔记，失败不能丢草稿（Task 3）。
4. 计时器与音频截止同时到零，只保存一次且不自动完成，后台时长不超截止（Task 2）。
5. 切换预设时队列已有缓冲，实际声响必须在下一拍换色且不破坏节奏（Task 6）。

## 文件边界与验证命令

主仓库为本文件所在的 foxgita 仓库，以下路径均相对此仓库。先记录 dirty diff 基线，再逐块修改；不要复制覆盖整份 PracticeDetailView 或 PracticeStore。新文件是否自动加入 target 以 project.pbxproj 实际同步组为准，不先假设。

新增文件以职责划分：
- `Services/MetronomeVisualPreferences.swift`：全局视觉/反馈偏好、默认及持久化。
- `Features/Practice/PracticeRuntimeCoordinator.swift`：用户命令、暂停原因、时钟/音频联动。
- `Features/Practice/PracticeNoteAutosaver.swift`：版本化防抖、flush 与保存状态。
- `Features/Practice/PracticeNoteSection.swift`：笔记与四个媒体入口。
- `Features/Practice/MetronomeVisualSettingsSection.swift`：新版视觉控件。
- `Features/Practice/MetronomeAdvancedSoundSheet.swift`：强拍增强/振动/闪拍。
- `Features/Practice/MetronomeFullscreenView.swift`：复用同一运行状态的大屏显示。
- `Services/PracticeAttachmentImporter.swift`：文件类型、私有复制及补偿。

以上均位于 `foxgita/`；相应测试放 `foxgitaTests/` 或 `foxgitaUITests/`。

统一单测命令（将 `<Suite>` 换为任务列出的 suite，多个 suite 重复传入 only-testing 参数）：

```sh
xcodebuild test -project foxgita.xcodeproj -scheme foxgita -destination 'platform=iOS Simulator,id=D411837A-75F5-4BE8-975C-1FD07C67C634' -derivedDataPath /tmp/gita-practice-ui-dd -only-testing:foxgitaTests/<Suite>
```

成功证据为退出码 0 与 `TEST SUCCEEDED`。新行为先以针对性测试证明旧代码失败，再实现；单纯外观通过截图验证，不写复制实现细节的测试。系统服务访问若被沙箱限制，使用受审查的提权执行相同命令，不把连接失败报成产品测试失败。

### Task 1：配置归属、拍号单位与全局偏好

**Files:** Create `foxgita/Services/MetronomeVisualPreferences.swift`, `foxgitaTests/MetronomeVisualPreferencesTests.swift`; Modify `Services/MetronomeMeter.swift`, `Services/MetronomeEngine.swift`, `Services/PracticeStore.swift`, `foxgitaTests/MetronomeMeterTests.swift`, `foxgitaTests/PracticeStoreTests.swift`（Services 实际位于 foxgita/ 下）。

**Interfaces:**
- 新增 `struct MetronomeVisualPreferences: Codable, Equatable`：`beatModuleEnabled`, `pendulumEnabled`, `highlightStrong`, `highlightMedium`, `highlightNormal`, `barCounterVisible`, `hapticsEnabled`, `flashEnabled`，均 Bool。
- 新增 `@MainActor @Observable final class MetronomeVisualPreferencesStore`，`init(defaults: UserDefaults = .standard)`，`private(set) var value: MetronomeVisualPreferences`，`func update(_ value: MetronomeVisualPreferences)`；单 key `gita.metronome.visualPreferences.v1`，编码含版本 1。
- `MetronomeMeter.supportedDenominators: [Int] = [2, 4, 8, 16]`；新增 `MetronomeEngine.setDenominator(_ value: Int)`，沿用 configured/pending 节奏模型；不要改变现有 subdivision rawValue。

- [ ] 写测试 `defaultsMatchNewPanel` 断言 true/false/true/true/true/false/true/false；`corruptDefaultsRecoverWithoutTouchingPractice`；`visualPreferencesSurviveStoreRecreation`；`soundRemainsPerPracticeItem` 保存 A/B 不同音色并验证互不污染；`denominatorUsesSupportedValues` 验证 6/8、无效 5/3→5/4、上下限。
- [ ] 用对应三个 suite 跑出新断言失败，记录为行为缺失而非构建环境失败。
- [ ] 实现偏好读写及引擎分母入口，保留 BPM 每拍 60/BPM 秒；沿用 PracticeStore 现有声音字段，无 schema 变更。默认未提供值按 spec 恢复；旧库不批量重写。
- [ ] 跑上述 suite 和 `MigrationTests`，确认已有记录/旧音色兼容映射不受影响。
- [ ] 审查本任务 diff 与基线，记录独立交付；仅在可明确隔离本人修改时提交，不自动 stage 既有修改。

### Task 2：独立练习计时与运行协调

**Files:** Create `foxgita/Features/Practice/PracticeRuntimeCoordinator.swift`, `foxgitaTests/PracticeRuntimeCoordinatorTests.swift`; Modify `PracticeDetailView.swift`, `Services/PracticeTimer.swift`, `Services/PracticeCountdown.swift`, `Services/MetronomeEngine.swift`, `Services/MetronomeTempoController.swift`, `Services/VideoRecorderService.swift`；测试 `PracticeTimerTests`, `PracticeCountdownTests`, `MetronomeEngineTests`。上述视图在 Features/Practice/，服务在 foxgita/Services/。

**Interfaces:**
- `@MainActor @Observable final class PracticeRuntimeCoordinator` 注入现有 timer/countdown/engine/tempoController/recorder 及保存闭包，通过窄协议适配实现以便 fake 测试；协议使用现有同名方法与状态，不复制服务实现。
- 命令 `func startPractice() throws`, `func pausePractice()`, `func resumePractice() throws`, `func setMetronomeEnabled(_ enabled: Bool) throws`, `func pauseRecordingOnly()`, `func resumeRecordingOnly() throws`, `func beginVideoPresentation()`, `func endVideoPresentation()`, `func handleCountdownCompletion()`, `func leavePractice() throws`, `func completePractice() throws`。
- 状态 `metronomeEnabled: Bool`、`recordingPauseReason: RecordingPauseReason?`（`.practice` / `.recording`）、`isPresentingPracticeTool: Bool`；保存闭包失败必须抛出并保留 pending。录音开始沿用 async start，成功后再启动计时。
- 新增 `MetronomeEngine.pausePlayback()` / `resumePlayback() throws`，区别于 stop；暂停保留正式小节序号，stop/new run 重置。新增 `struct PracticeBarCounter`，`private(set) var displayedBar: Int?`，`mutating func consume(bar: Int, isPreparatory: Bool)`、`mutating func reset()`；同一小节的重复事件不重复增加，首次正式事件显示 1，训练预备不累计。它不依赖 UI 刷新；暂停保留该值。

- [ ] 用注入时钟/fake 服务写 `silentPracticeAccumulatesTime`、`mainResumeDoesNotResumeManuallyPausedRecorder`、`recordingStopKeepsPracticeRunning`、`cameraPresentationDoesNotLeavePractice`、`cameraReturnDoesNotDoubleCountElapsed`、`duplicateCountdownCompletionSavesExactlyOnce`、`completionWhileCameraVisibleCapsElapsedAtDeadline`、`failedSaveKeepsPracticeIncompleteAndPendingMedia`。
- [ ] 跑新 suite 证明失败，然后实现 spec 的动作矩阵；在现有 onDisappear/scenePhase/中断入口接入同一协调命令，避免保留两套并行保存逻辑。
- [ ] 补 `PracticeBarCounterTests`：正式第一小节 1，预备排除，pause/resume 保留，stop/new run 重置，声音静音不阻止推进；补引擎 pause/resume 的真实时间线断言，不以 UI tick 推算。
- [ ] 跑 Runtime、BarCounter、Timer、Countdown、Engine、TempoController suite；音频 cutoff 和 wall-clock 合并完成，保留现有 deadline 机制。
- [ ] 独立审查运行协调改动，确认录音自身 pause 与系统 interruption 仍为不同动作，再记录/隔离提交。

### Task 3：笔记自动保存与统一完成

**Files:** Create `foxgita/Features/Practice/PracticeNoteAutosaver.swift`, `foxgitaTests/PracticeNoteAutosaverTests.swift`; Modify `PracticeDetailView.swift`, `Services/PracticeStore.swift`, `foxgitaTests/PracticeDetailStateTests.swift`, `foxgitaTests/PracticeStoreTests.swift`。

**Interfaces:**
- `@MainActor @Observable final class PracticeNoteAutosaver`，`enum State { case saved, saving, failed(String) }`；`init(save: @escaping (String) async throws -> Void)`，`func schedule(_ text: String)`、`func flush() async throws`。延迟 600ms，测试注入可控等待函数，不用 sleep 等真实时间。
- 保存请求带递增版本，完成只确认对应版本；同一项写入串行，flush 等最新版本；返回和完成消费 Task 2 的保存结果。

- [ ] 测试 `debounceSavesLatestText`、`oldCompletionDoesNotMarkNewDraftSaved`、`flushWaitsForLatestText`、`saveFailurePreservesDraftAndCanRetry`、`autosaveDoesNotMarkCompleted`；历史入口仍不能改累计时长与完成状态。
- [ ] 跑 Autosaver、DetailState、Store suite 验证新行为失败。
- [ ] 实现自动保存，将退后台/返回/上下完成接到 flush；图片与媒体沿用独立立即写入，不用 note 防抖吞掉文件错误。
- [ ] 跑同组 suite 通过，并检查“保存中/已保存/保存失败”状态只在正确时机展示。
- [ ] 审查竞态与 Store 既有修改兼容，记录/隔离提交。

### Task 4：十场景界面与完整 MT-04

**Files:** Modify `foxgita/Features/Practice/{PracticeDetailView,MetronomeDisplayCard,MetronomeSoundSheet,MetronomeSettingsSheet,MetronomeSpeedSheet,CountdownSettingsSheet}.swift`, `foxgita/Localizable.xcstrings`; Create 上述文件边界列出的 NoteSection、VisualSettingsSection、AdvancedSoundSheet、FullscreenView 及两个 `Assets.xcassets/Metronome*` imageset；新增 `foxgitaUITests/PracticeSettingsUITests.swift`。

**Interfaces:**
- 保留 `MetronomeSoundSheet(metronome:onDone:)` 现有入口语义，增加 `visualPreferences: MetronomeVisualPreferencesStore`, `onRecord: () -> Void`, `onExpand: () -> Void` 注入，避免 Sheet 自己创建录音器/第二引擎。
- `MetronomeFullscreenView` 注入同一 engine、visualPreferences 与 counter；`MetronomeAdvancedSoundSheet` 接同一 engine/全局反馈偏好；DisplayCard 新增 `onSoundSettings` 及启用节拍器命令。

- [ ] 以稳定 accessibilityIdentifier 写 UI 测试：齿轮能打开完整 MT-04；编号/卡片同步；± 端点禁用；beat+pendulum 同时选中；跨练习视觉保持、声音不同；关闭/展开返回不停止练习。先证明旧界面缺入口。
- [ ] 按 spec 组合 PR-01–03，提取 NoteSection，保留步骤增删与四入口真实命令；整页安全区/键盘滚动正确，不硬编码屏高。
- [ ] 完整重建 MT-04、更多与全屏，导入两张透明 PNG；复用系统字体/Gita token，局部白底；数字和状态仍为原生文本，不把整面板做截图。
- [ ] 对齐 MT-01/02/03 以及 CD-01/02/03，分母±接 Task 1，倒计时两个按钮分别调用保存与启动，运行状态接 Task 2。
- [ ] 在标准屏、SE 3、大字号和 VoiceOver/Reduce Motion 下截图与手检；UI suite 必须 `TEST SUCCEEDED`，截图证明十场景都有落点。
- [ ] 记录本任务 diff/截图并隔离提交，截图与构建产物不进入产品 target。

### Task 5：真实波形、文件导入与媒体保存

**Files:** Create `foxgita/Services/PracticeAttachmentImporter.swift`, `foxgitaTests/PracticeAttachmentImporterTests.swift`; Modify `Services/AudioRecorderService.swift`, `Services/VideoRecorderService.swift`, `Services/RecordingStore.swift`, `Features/Practice/PracticeDetailView.swift`, `Features/Practice/PracticeNoteSection.swift`；回归 `NoteImageStoreTests`。

**Interfaces:**
- `AudioRecorderService` 新增只读 `inputLevels: [Float]`（0…1、最近 32 个电平），录音成功后启用 metering，暂停冻结、停止清空，不记录原始采样或额外音频文件。
- `PracticeAttachmentImporter.importFile(at url: URL, practiceItemID: UUID) async throws -> ImportedPracticeAttachment`；返回枚举定义为 `case image(NoteImage)` 与 `case media(fileName: String, bytes: Int, durationSec: Int, label: String)`，只传输导入结果，不增加持久化附件模型；保存关系仍由 PracticeStore 执行。
- fileImporter 仅图片/audio/movie UTType，复制时平衡 security-scoped access；任务取消及持久化失败补偿仅清理本次新文件。

- [ ] 测试 `cancelledImportDoesNotCreateAttachment`、`unsupportedOrCorruptFileDoesNotWriteRelation`、`databaseFailureRemovesOnlyNewFile`、`threeImageLimitIncludesImportedPhotos`、`repeatedImportSubmissionDoesNotDuplicateMedia`，使用临时目录与假元数据读取，不依赖真实麦克风权限。
- [ ] 跑 Importer 和 NoteImageStore suite 证明行为缺失后实现文件流程，媒体 pending 只在 Store 成功后 detach。
- [ ] 接真实电平波形与权限/取消/失败 UI；检查 AVAudioRecorder.record() 返回失败不标记开始成功；录像保存/取消遵循 Task 2，不按视频 duration 重算练习累计。
- [ ] 跑文件 suite、Store suite、现有媒体 UI 流程；真机检查动态波形、录音暂停冻结、相机取消与权限拒绝，记录无法在模拟器验证的项。
- [ ] 审查文件所有权和媒体失败传播，记录/隔离提交。

### Task 6：音色调音与实际切换时序

**Files:** Modify `foxgita/Services/MetronomeEngine.swift`, `MetronomeSoundBank.swift`, `MetronomeSoundPreset.swift`（后两者同在 foxgita/Services/），`foxgitaTests/MetronomeEngineTests.swift`, `MetronomeSoundAssetTests.swift`, `MetronomeSoundPresetTests.swift`；候选输出放 `.scratch/practice-ui-audio-review/`，正式文件沿现有音频资产路径；许可证随资产更新。

**Interfaces:**
- 保持 `setSoundPreset(_:)`, `setVolume(_:)`, `preview(bars:)`；新增 `setTemporarilyMuted(_ value: Bool)`，不改变保存音量；`flashOnAccent` 读取独立开关而非 preset == handClap。
- 正式小节/练习时长/训练状态不由 preview 修改；已播放时 preview 不创建另一个 run。

- [ ] 测试 `previewDoesNotAdvancePracticeOrFormalBars`、`presetChangePreservesNextBeatFrameAndBar`、`mutePreservesSavedVolumeAndClock`、`clapDoesNotForceFlash`；时间线测试覆盖已排队 buffer，不只 assert soundPreset 属性。
- [ ] 跑 Engine/Asset/Preset suite 失败后实现状态与排程联动；若要重排 player 缓冲，保持 sample-time 原点和下一拍位置，不能 stop/start 整个引擎造成相位重置。
- [ ] 生成同节奏木质/电子/强拍 A/B 试听文件与许可、峰值、长度报告；保留原素材供比较，不直接覆盖。向用户展示可播放文件并执行已确认的 Q7 音色选择评审。
- [ ] 仅将用户选定素材写入正式 14 份资源，保持七 rawValue、70ms 契约和预加载；未选定期间继续其余任务，不能将候选当已批准资产。
- [ ] 跑声音 suite，真机检查低速/高速/密集细分、强普通拍区分、实际切换无漏拍/叠音；记录长时稳定性证据，再审查/隔离提交。

### Task 7：全流程集成、审查与交付证据

**Files:** Modify `foxgitaUITests/PracticeFlowUITests.swift`, 新增 `foxgitaUITests/PracticeSettingsUITests.swift` 的剩余场景；Create `docs/qa/2026-10-28-practice-ui-rebuild-verification.md`；更新本计划勾选状态和必要用户文档。

**Interfaces:** 使用 Task 1–6 已定义状态与命令，不引入第二个保存/时钟路径；可复用现有测试 fixture，不把测试专用功能暴露给正式用户。

- [ ] 补端到端场景：创建/继续→无声计时→录音→主暂停→独立暂停→笔记输入→返回重进→倒计时结束未完成→用户完成；历史查看、全局偏好跨练习及声音隔离也有断言。
- [ ] 运行全部 `foxgitaTests`，然后运行 PracticeFlow/PracticeSettings UI suites；新增改动失败时只修相关问题，不重复扩大无关测试。若失败来自既有 dirty baseline，记录基线对照，不吞掉失败。
- [ ] 十场景截图对照 Figma，逐项确认 MT-04 完整面板、白底、字体层级及所有按钮有真实操作；SE 3 大字号再验长页面滚动。
- [ ] 真机测试录音/录像、后台/锁屏、耳机丢失、来电、音频服务重置、音色快速切换与两小时稳定基线；未具备设备时标为未验证，不伪报通过。
- [ ] 使用 code-reviewer 和 swift-reviewer 做代码变更审查，修复实际问题后运行受影响检查；检查持久化失败无数据丢失，避免以提交状态代替测试结果。
- [ ] 输出代码变更范围、测试命令与结果、截图、音色选择记录和未验证项；不自动发布、推送或混入其他工作。

## 规格覆盖与自检

Q1/Q2→Task 1；Q3→Task 1/4；Q4→Task 2；Q5→Task 3；Q6→Task 4/6；Q7→Task 6；Q8→Task 4；Q9→Task 1/4；Q10→Task 2/5；Q11→Task 2/4；Q12→Task 4/6；Q13→Task 5。跨场景验证在 Task 7。

已有训练/后台/迁移约束分别由 Task 2/6/1 保留；无障碍和窄屏由 Task 4 验证；媒体权限/文件补偿由 Task 5 验证；五项 Review Focus 均有对应测试。

建议 Native 执行：运行协调、笔记保存和巨大既有 DetailView 相互依赖，保持同一实现上下文更便于保护当前未提交工作；阶段完成后独立审查最终代码。此处是调度建议，具体方式由后续实施会话确定；产品实现及剩余验收见上方实施状态和验证记录。
