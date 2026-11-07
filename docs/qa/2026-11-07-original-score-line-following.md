> 2026-11-07 更新：用户已纠正为自动读取并直接跟练；手工标记流程不再作为当前入口。最新验收见 [原谱自动读取](2026-11-07-original-score-automatic-reading.md)。以下保留历史记录。

# 原谱跟弹开发与验证记录

日期：2026-11-07。需求依据：[开发规格 v1.0](../superpowers/specs/2026-11-06-original-score-line-following-spec.md)。

## 实现

- 创建练习中保留自由/跟谱选择，跟谱再选曲谱跟练/原谱跟弹；原谱 CTA 进入上传来源选择。工具和已有练习入口复用同一材料库。
- `OriginalScoreDocument` / `OriginalScoreRun` / `OriginalScoreLibrary` 独立表达手动谱行。原件位于 `OriginalSources/profile/source`，不会投影成待识谱任务。
- 上传图片/PDF、草稿自动保存、连续框选多行、几何调整、拍数、小节快捷输入、手动排序与显式入库。新行首行 1 小节，后续沿用前行拍数；未标页可查看。
- 分母拍 BPM、半拍输入、弱起与全曲相位，固定 3 秒准备及取消、整行匀速、范围、循环、调速暂停、静音不断时钟。
- 原件与不可变标记版本保留；几何修订保持同次精确位置，结构修订重置；跨次行首恢复；隐藏材料后历史可查看。
- 复用 `PracticeStore` 的实际时长幂等提交。原谱历史与待提交 checkpoint 原子落盘，再提交今日练习并标记完成；分片跨天，保留发生日期。已有练习材料卡可显示原谱版本、范围、速度并查看当时谱面。

数值安全补充：总拍数上限为 10 亿拍，用于约束半拍与音频 host-frame 整数转换；超大数字不能进入音频调度器。该上限远大于实际 20 页曲谱需求。播放不请求麦克风或远端识谱。

## 验证

| 检查 | 结果 |
|---|---|
| iOS Simulator Debug 通用构建 | 通过，arm64 / x86_64 |
| 原谱核心针对性测试 | 11 / 11 通过 |
| 完整 Swift Package 核心测试 | 137 / 137 通过，19 suites |
| 原生 PracticeStore 集成 | 2 / 2 通过：今日复用、历史/完成项隔离、幂等计时、笔记/声音保留 |
| 原生上传到跟弹端到端首次重跑 | 1 / 1 通过：上传、框行、保存、准备取消不计时、播放、关闭、重开 |
| 最终原生针对性验收 | 18 / 18 单元用例、2 / 2 UI 用例通过；含连续两行、完整 3 秒准备、创建页直接上传与 5 个已有视频生成用例 |
| 完整原生单元套件（正确签名） | 947 项：904 通过、42 跳过、1 个已有用例进程退出；该用例隔离复核通过，批跑结果仍不标记为全绿 |
| 完整原生 UI 回归（分组执行） | 70 项：53 首轮通过、9 跳过、8 并行失败；8 项随后串行复核全部通过，批跑仍不标记为全绿 |
| SwiftLint | 环境未安装；Swift 编译检查已执行 |

TDD 记录：模型、准备计时、草稿入库、同次修订精确恢复先出现编译失败；超大输入校验先出现预期失败，再实现并验证通过。测试使用公开模型接口与真实临时目录。

## 代码审查

按 code-review 分开执行 Standards 与 Spec 两轴，修复后均无未解决发现。

### Standards

0 项未解决发现，无 P1/P2 阻塞。已补上超大拍数校验、相位归一化、原子写历史与日志、单次位置扫描、跨天固定日期和保存失败后的中断监听。最终复审仅只读，不重复跑测试。

### Spec

0 项未解决发现。已修正入口暂停前捕获设置、同次修订与跨次打开的区分、已有练习原谱关联展示及创建 CTA 直达上传来源。两轴分别复审通过。

## 验证产物

临时原生测试结果：`/private/tmp/gita-original-score-ui-rerun.xcresult`、`/private/tmp/gita-original-score-full.xcresult`。核心日志：`/private/tmp/gita-original-score-full-core.log`。截图来自 UI 测试生成的谱页，不使用用户私人谱页。

[跟弹页原生截图](original-score-line-following/player.png)。最终针对性结果：`/private/tmp/gita-original-score-final-targeted.xcresult`。

首次完整原生测试使用 `CODE_SIGNING_ALLOWED=NO`，若干已有 Keychain 用例产生 `-34018` 权限错误；改用 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` 后，凭据/媒体生成 9 项、下一次练习/识谱/旧播放器 14 项及视频生成 5 项复核均通过。完整签名单元测试另外执行，以区分签名环境失败与代码回归。

正确签名的完整单元结果：`/private/tmp/gita-original-score-full-unit-signed.xcresult`，统计 947 项。唯一失败为 `PracticeStoreInvocationTests.savePracticeItemMarksInvocationCompleteOnce()`：`Test crashed with signal trap`；其测试文件及 AI 调用记录模块本次未修改。随后同一签名版本隔离运行该用例，通过（`/private/tmp/gita-original-score-invocation-isolated.xcresult`）。保留批跑失败事实，不用单独重跑覆盖原结果。

完整 UI 回归分组续跑已结束：`/private/tmp/gita-original-score-remaining-ui.xcresult`，61 项中 44 通过、9 跳过、8 失败。此前通过的方案 5 项、节拍器 2 项，加上最终原谱 UI 2 项，合计覆盖 70 项。已通过的分组不重复执行；最初串行命令在分组切换后主动结束，以降低等待时长。

并行批跑中，旧暗色双谱用例失败于“跟谱设置”导航栏断言（尚未进入后台暂停步骤），旧建议练习名称输入失败于键盘焦点。两者在同一签名版本上串行复核均通过：`/private/tmp/gita-original-score-entry-regression-recheck.xcresult`（2 / 2），无需为这些失败修改产品代码。批跑失败与复核结果分别保留。

其余 4 条并行失败（独立节拍器、工具目录返回、建议练习续练、调音器实时信号）串行复核也全部通过：`/private/tmp/gita-original-score-legacy-regression-recheck.xcresult`（4 / 4）。原有练习详情持续播放测试通过，含固定 600 秒观察，总执行约 643 秒。没有为这些复核修改工具、调音器或 AI 建议模块。

收尾阶段新增的 2 条创建页失败中，一条发生在测试 App 启动阶段（系统后台断言超时），另一条是等待创建页标题超时。独立复核均通过：`/private/tmp/gita-original-score-create-sheet-recheck.xcresult`（2 / 2）。因此并行失败的 8 条 UI 用例均有通过的串行复核记录，但不能据此宣称完整批跑已经通过。

[结构化验证摘要](original-score-line-following/validation-summary.json) 保留计数、复核结果与本次提交范围。跳过项主要需要外部谱页、服务或设备条件；本次未伪造这些条件。

本轮工作区原有跟谱、节拍器、AI 等未提交改动保留；提交范围以本次原谱实现和必要接入/测试为准。

功能提交为 `5dc328f`（`codex/follow-score-practice`）。这是基于现有工作区的增量提交：先前未提交的跟谱基础文件仍保留在工作区，构建与测试使用完整工作区；本记录不声称已验证只检出该提交即可独立构建。
