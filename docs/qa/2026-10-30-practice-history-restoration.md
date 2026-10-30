# 日期选择与历史练习恢复验收

日期：2026-10-30。设备：iPhone 17 模拟器，iOS 26.5。

结果：实现完成，最终 5 个 UI 场景全部通过，代码审查通过。

## 已确认的范围

- 日期区域左右翻周；卡片标题区域左右切换方案。
- 之前 26 周到本周，共 27 周；历史周自动选周一，回本周自动选今天。
- 点击日期切换下方练习，日期状态区分今天、选中日与有练习日。
- 历史页展示当日全部有效事实，包括方案分段，并标注日常练习 / 方案练习 / 清单训练来源。
- 今日清单保留未开始计划，继续排除独立方案分段；打卡统一按有效练习计算。
- 保留原历史详情内容编辑和显式保存能力；禁止历史继续计时与新增录音。

## 实现与回归依据

日期和周状态连接到现有 PracticeView；历史查询和持久化仍使用原始 PracticeItem，没有新增存储或复制练习事实。

周历和方案轮播保留原生横向 ScrollView。日期区域翻周，标题区域切方案；周历首尾各增加一个仅显示最近有效周的边界副本，吸收越界滑动后立即归位，防止手势串到外层。实际可浏览范围仍为 27 周，副本不接受点击且对辅助功能隐藏，没有 UIKit 手势探针。仅用户滑动提交日期选择，初始布局与程序定位不能误切到最早周。

测试夹具同时要求 Debug、`-UITesting` 和 `-PracticeHistoryFixture`，使用现有内存数据库测试隔离，不向日常练习资料写入验收数据。

## 验证记录

- 先写回归：日期区域不可点击的 UI 场景失败；历史空计划混入、今日方案分段混入两条单测按预期失败。
- 首轮恢复后：57 项日期、统计与详情单测通过；点选日期、返回今天与紧凑卡片往返通过。
- 实际发现同轴滚动竞争，边界副本修复后，当前周和最早历史周越界均保持日历；纵向拖动日期区域仍滚动首页。
- 全量执行 628 项单测（80 个套件），616 项通过，12 项因关闭签名导致钥匙串 `NSOSStatusErrorDomain -34018` 失败。启用模拟器本地签名重跑涉及的 4 个完整套件，17 项全部通过，没有修改钥匙串实现。
- 最终构建及 5 个 UI 场景全部通过：日期点选 / 回到今天、翻周 / 两端边界、紧凑方案与日历往返、历史日常和方案来源 / 详情及 Tab 返回保持、日期区域纵向滚动。
- 通用代码审查对最终纯 SwiftUI 版本给出 APPROVE；Swift 专项审查工具因强制 SwiftPM 前置检查与 Xcode 项目不兼容停止，实际构建使用 Xcode。

钥匙串环境复验覆盖的原失败项：

| 套件 | 原失败项 | 复验 |
| --- | --- | --- |
| LLMCredentialsStoreTests | saveLoadClearRoundTrip、isConfiguredRequiresAllFields | 整套 2 项通过 |
| MediaReviewGeneratorTests | prepareFailedMaps、clientUnauthorizedMaps、fileMissingMaps、successPassesImagesAndContextText、videoLabelOmitsEmptyNoteAndSteps | 整套 7 项通过 |
| NextSessionGeneratorTests | mapsVisionUnauthorized | 整套 3 项通过 |
| VideoDiagnosisGeneratorTests | prepareFailedMaps、clientUnauthorizedMaps、fileMissingMaps、successReturnsDraft | 整套 5 项通过 |

本次是模拟器验收，未新增真机测试或跨日驻留测试。日期 / 周边界计算由既有统计单测覆盖。

## 截图与原始结果

- [历史练习与来源](screenshots/2026-10-30-practice-history/historical-sources.png)
- [历史周与空态](screenshots/2026-10-30-practice-history/previous-week.png)
- [本周日期选择](screenshots/2026-10-30-practice-history/current-week.png)

本机原始结果（临时目录）：`/tmp/gita-history-acceptance.xcresult`（最终 5 项 UI）、`/tmp/gita-history-final.xcresult`（全量单测首轮）、`/tmp/gita-history-verify.xcresult`（钥匙串 17 项复验；此轮手势 UI 失败随后修复，最终结果以前者为准）。

## 相关规格

[日期恢复规格](../design/2026-10-30-practice-history-calendar-restoration.md)
