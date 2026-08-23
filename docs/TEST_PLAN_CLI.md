# Gita 命令行自动化测试计划

> 目的：确认核心逻辑与主流程冒烟未坏，不依赖手点真机。  
> 执行环境：macOS + Xcode + iOS Simulator（默认 `iPhone 17`）  
> 工程：`foxgita.xcodeproj` · Scheme：`foxgita`

---

## 1. 范围与不测项

| 纳入 | 不纳入（需真机/手测） |
|---|---|
| 单元：统计、计时器、Store、Schema 迁移 | 麦克风真实录音质量、系统相机录视频 |
| UI 冒烟：启动、进详情、推荐 Sheet、设置外观 | 周历选日锁定、左滑编辑删除、录音中面板 |
| 编译与签名以外的逻辑回归 | 来电打断、后台续时手感、App Store / TestFlight 分发 |

---

## 2. 前置条件

1. 已安装 Xcode，命令行工具可用：`xcodebuild -version`
2. 模拟器可用：`xcrun simctl list devices available | grep iPhone`
3. 工作目录：仓库根目录 `/Users/haizei/work/AI/program/gita/foxgita`

若无 `iPhone 17`，改用列表里任意可用 iPhone 模拟器名称。

---

## 3. 执行步骤与验收标准

### Step A — 环境自检

```bash
xcodebuild -version
xcodebuild -project foxgita.xcodeproj -list
xcrun simctl list devices available | grep 'iPhone'
```

**通过**：能看到 Scheme `foxgita`，Targets 含 `foxgita` / `foxgitaTests` / `foxgitaUITests`。

### Step B — 仅单元测试（逻辑）

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests \
  test
```

| 套件 | 预期 |
|---|---|
| `StatsAggregatorTests` | 连续日、周点、周一边界、环比、按时长进位等通过 |
| `PracticeTimerTests` | 墙钟计时、暂停不计时、后台不丢时通过 |
| `PracticeStoreTests` | seed / 激活模板 / finish 不变量 / 回滚 / reset / `createFromAIDraft` / `beginOpenSession` / `appendRecording` / `updateOpenSession` 通过 |
| `MigrationTests` | V2→V7 / V5→V7 / V6→V7 磁盘库迁移不丢数据；新行 profileId 默认为空直到 prepare 回填；V6 false → undecided |
| `AIPracticeDraftTests` | normalize 标题/分类/分钟/步骤钳制通过 |
| `LLMCredentialsStoreTests` | Keychain 读写清除与 `isConfigured` 通过 |
| `VisionPracticeClientTests` | URL 拼接、成功解析、401、非法 JSON、`response_format` 重试通过 |
| `SkillRegistryTests` | 内置三 id、version 1.1.0、只读 scopes、write deny、缺 id 为 nil |
| `AITransportTests` | URL 拼接、fence、401、非法 chat JSON、timeout、response_format 只降级一次 |
| `MemoryRepositoryTests` | profileId 必填、跨 Profile 隔离、过期/软删不可见、同 key 覆盖 |
| `MemoryContextBuilderTests` | 空块、包装分隔符、goal 先于 ability、预算截断 |
| `MemoryContextTests` | consent 非 enabled 不注入；打开后图片 Skill 不含 ability |
| `MemoryStoreTests` | 未启用不能添加；增删改摘要 |
| `MemoryConsentCoordinatorTests` | 已决定不弹；未选择启用后 proceed |
| `MemoryConsentCopyTests` | 四条隐私文案与按钮文案 |
| `MemoryDebugSeederTests` | 无 flag 不写；flag 写入附录 B 三条并 `consent == enabled` |
| `ImageStepGeneratorTests` | JPEG 压缩与空图/超量/未配置校验通过 |
| `MediaReviewDraftTests` | highlight / focus / nextAction 去空白、空段失败、80 字截断通过 |
| `MediaReviewClientTests` | 成功解析、401、非法 JSON、`response_format` 重试通过 |
| `MediaReviewGeneratorTests` | 波形/抽帧 JPEG、未配置、文件缺失校验通过 |
| `VideoDiagnosisDraftTests` | normalize 窗口钳制、去空白、最多 5 段、空 summary 失败通过 |
| `VideoDiagnosisClientTests` | 成功解析、401、非法 JSON 通过 |
| `VideoFrameSamplerTests` | 短片段三锚点、长片段上限 10、零时长通过 |
| `VideoDiagnosisGeneratorTests` | 未配置、prepare 失败、401 映射通过 |
| `ReviewJobRunnerTests` | 顺序写回、401 停后续、单条失败继续；`.mov` 写 `videoFindings` 通过 |
| `AlbumDurationGateTests` | 29/0 拒绝、30/600 通过、601 拒绝 |
| `AlbumVideoImporterTests` | 保留扩展名、缺文件、非法扩展名不写盘、`.m4v` 孤儿清理 |
| `PracticeClipQueryTests` | 已删过滤、音视频分类、`createdAt` 倒序、id 去重、`8月16日 14:32` |
| `RecordingStoreTests` | 写入后 `fileExists` true，删除后 false |
| `AudioSessionCoordinatorTests` | apply 失败回滚计数；成对 acquire/release；record+playback 仍 prefersPlayAndRecord |
| `MetronomeEngineTests` | `bump(1)` 钳制；acquire 失败 `isPlaying == false`；start/stop/start 引擎 running 且无第二份 pump |
| `PracticeResumeQueryTests` | 无历史隐藏行；有效 session 覆盖 default；跳过无效/已删；nextAction 优先；28 字截断；BPM 钳制 |
| `JustCompletedCopyTests` | 分钟进位；0 分钟+笔记/媒体为「不足 1 分钟」；摘要不含 0 条 |
| `AppRouterTests` | `clearJustCompleted` 清 id |

**通过**：日志出现 `TEST SUCCEEDED`，无 `✘` / `error:`（业务测试失败）。

### Step C — 全量测试（单元 + UI 冒烟）

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

| UI 用例 | 预期 |
|---|---|
| `testLaunchShowsTodayPractice` | 见「今日练习」 |
| `testStartFirstTaskOpensDetail` | 进详情见节拍器 |
| `testRecommendSheetCanBeOpenedAndDismissed` | 打开/关闭推荐 Sheet |
| `testRecommendSheetShowsImageGenerateEntry` | 推荐 Sheet 可见「拍摄/照片」 |
| `testSettingsAppearanceSegmentExists` | 设置页有主题外观 |

**通过**：单元 + UI 全部绿色，`** TEST SUCCEEDED **`。

### Step D — 结果归档（可选）

```bash
# 将本次完整日志落到文件，便于对比
xcodebuild ... test 2>&1 | tee /tmp/gita-cli-test-$(date +%Y%m%d-%H%M%S).log
```

---

## 4. 判定总表

| 级别 | 条件 | 结论 |
|---|---|---|
| P0 逻辑健康 | Step B 全绿 | 统计/计时/写库/迁移未坏 |
| P0 可用冒烟 | Step C 全绿 | 主界面与关键跳转未坏 |
| 失败需停 | 编译失败或任一测试失败 | 先修再合入/再发真机包 |

---

## 5. 常见失败处理

| 现象 | 处理 |
|---|---|
| `Unable to find a device matching ... iPhone 17` | 换 `-destination` 为实际模拟器名 |
| Simulator 服务连不上 | 打开 Xcode 一次，或重启模拟器：`xcrun simctl shutdown all` |
| UI 超时找不到控件 | 确认 seed 数据仍在；冷启动模拟器再跑 |
| 签名相关报错 | CLI 测模拟器一般不需 Team；若混入真机 destination 则改回 Simulator |

---

## 6. 本次执行记录

| 项 | 内容 |
|---|---|
| 执行时间 | 2026-08-04 09:13–09:16（UTC+8） |
| 环境 | Xcode 26.6 (17F113) · Destination: iPhone 17 Simulator |
| Step A | 通过：Targets `foxgita` / `foxgitaTests` / `foxgitaUITests`，Scheme `foxgita` |
| Step B | **通过**：33 tests / 4 suites（StatsAggregator、PracticeTimer、PracticeStore、Migration） |
| Step C | **通过**：单元 33 + UI 4（PracticeFlowUITests 全部 passed） |
| 日志 | 单元：`/tmp/gita-cli-test-unit-20260804-091304.log`；全量：`/tmp/gita-cli-test-full-20260804-091508.log` |
| 结论 | **P0 逻辑健康 + 主流程冒烟通过**，命令行自动化未发现回归 |
