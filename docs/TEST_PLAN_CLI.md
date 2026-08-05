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
| `PracticeStoreTests` | seed / 激活模板 / finish 不变量 / 回滚 / reset 通过 |
| `MigrationTests` | V2→V3 磁盘库迁移不丢数据通过 |

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
