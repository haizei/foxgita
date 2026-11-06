# 建议练习｜集成验证记录

2026-11-06，iPhone 17 Pro Simulator（GitaTests），iOS 26.5。

已按用户最终选择完成集成：每份档案最多一条未完成建议；确认重点后，项目更新冲突或失败单独提示和重试。建议卡复用「今日练习」的卡片样式；离开练习即暂停，首页显示「已暂停／继续」。

## 最终验证

- `/private/tmp/gita-next-focus-final-input.xcresult`：新增 5 项补充输入与取消回归全部通过，0 失败、0 跳过。覆盖补充内容不直接成为行动、手动降级重入、晚结果保护、取消项目更新意图，以及编辑触发传输取消时不写入虚假失败。
- 与下方 36 项核心及 4 项界面验证合并为 45 项不同用例。Swift 与规格两轴复审均通过，未留阻断问题。

- `.scratch/suggested-practice-final.xcresult`：40 项通过，0 失败、0 跳过。包含 36 项核心测试和 4 项界面测试。
- `.scratch/suggested-practice-final-core.xcresult`：最终取消回调保护修改后，36 项核心测试再次全部通过，0 失败、0 跳过。界面与集成文件在两次验证之间没有变化。
- 两份结果均通过 `xcresulttool get test-results summary` 核验为 `Passed`。测试设备为独立模拟器 `FA292B54-4541-48CD-806B-7417D1C88AE3`，避免与另一聊天共用运行中的模拟器。
- 核心测试选择 `NextFocusStoreTests`、`PracticeHomeStateTests` 和 `PracticeRuntimeCoordinatorTests`。覆盖草稿与确认分离、人工编辑保护、档案隔离、写入失败保护、跳过和撤销、重复进入、关联写入失败后的重试、跨天建立练习事实、来源失效、行动生命周期及项目更新冲突。
- 两项审查回归已通过：项目重试不能恢复已完成的行动或替换另一行动；补充输入保存失败后，旧生成结果不能切走补充状态。已取消或失效的请求也不能写入旧错误。
- 独立代码审查和 Swift 复查通过，未留阻断问题。

## 界面与截图

- `SuggestedPracticeUITests.testCompleteConfirmAndResumeSuggestedPractice`：验证无建议时无占位卡、完成练习后手填确认、首页待开始、进入后不自动计时、暂停后显示继续、重入原面板仍暂停。
- `SuggestedPracticeUITests.testGeneratedFocusRequiresConfirmation`：AI 草稿需明确保存后才成为建议。
- `SuggestedPracticeUITests.testInsufficientInputGeneratesBeforeConfirmation`：信息不足时先补充再生成，不能直接把补充文本确认成建议。
- `PracticeFlowUITests.testSavePreservesUnstartedPracticeAndOnlyBottomCompletes`：原有保存与明确完成行为保持成立。
- 已导出 7 张测试截图，索引见 [manifest.json](2026-11-06-suggested-practice-screenshots/manifest.json)。已目视核对首页 [待开始](2026-11-06-suggested-practice-screenshots/84F83C3A-69BD-4240-9403-3DD2A7F8CEB5.png)、[已暂停](2026-11-06-suggested-practice-screenshots/63E2A9E7-FBBF-4017-9F7E-F7B9B08AE9C9.png)与 [完成后待确认](2026-11-06-suggested-practice-screenshots/C4353CC1-EA6B-4741-A940-0280656CFE4F.png)。无建议状态由交互断言验证。

## 验证边界

本记录中的 AI 界面用例使用明确启用的模拟返回。后续已完成 [真实 AI 完整流程联调](2026-11-06-suggested-practice-live.md)，并修正占位步骤与内部字段出现在生成结果中的问题；24 项相关验证通过。真机验证尚未执行。早期共享文件调整期间的编译失败和中断测试不计入上述通过数量。

## 工作区与提交范围

本次验证基于完整共享工作区，其中仍有并行跟谱、节拍器等未提交改动。本次提交仅包含练后总结、建议重点及必要首页／练习页集成，保留其他工作区修改。没有运行真实 AI 供应商请求。
