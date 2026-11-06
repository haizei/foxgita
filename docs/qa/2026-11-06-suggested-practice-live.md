# 建议练习｜真实 AI 完整流程联调

2026-11-06（Asia/Shanghai），iPhone 17 Simulator / iOS 26.5，模型 `qwen3.8-max`。

已通过正常 App 客户端跑通：完成练习 → 真实生成本次总结与下次重点 → 用户确认保存 → 首页「建议练习」。测试使用独立档案和测试练习内容，沿用模拟器已保存的 HTTPS 接口配置及 Keychain 凭据。

## 真实返回与保存结果

练习为 `C to G chord transition`，原设置为 80 BPM，实际计时 2 秒，没有练习备注或媒体分析。

- 总结：你记录了练习对象为 C 到 G 和弦切换，并保留了 80 BPM 的原有速度设置。
- 重点：下次按 80 BPM 继续做 C 到 G 和弦切换。
- 依据：记录包含明确练习对象和原速度；步骤为通用占位，因此只建议继续该对象。

点击完成至测试观察到生成结果约 33.27 秒，包含界面操作和读取耗时，不作为纯接口延迟。草稿的 `generated` 为真，首页行动原文与生成草稿一致，来源身份相同，没有生成错误。

[持久化核对结果](2026-11-06-suggested-practice-live/persisted-result.json)、[界面测试报告](2026-11-06-suggested-practice-live/verified-screenshots/7075F528-F2A1-4BA2-93F9-811DDDB1B1C9.json)、[生成总结与重点截图](2026-11-06-suggested-practice-live/verified-screenshots/C9850BF6-8916-4EE8-B41C-2C901D3928D1.png)、[确认后的首页截图](2026-11-06-suggested-practice-live/verified-screenshots/4B9354FF-1FB6-4E8F-B9C3-CCFD27308A44.png)。两张最终截图已目视核对。

## 联调发现与修正

初次真实流程已成功生成和保存，但返回把默认步骤「新步骤」当成具体依据，建议改写步骤，依据里还出现了 `existingBPM`。原返回保存在 [首轮结果](2026-11-06-suggested-practice-live/pilot-result.json)。

据此收紧 `NextFocusClient.systemPrompt`：重点必须是实际练习动作，通用占位步骤不能作为具体训练依据，总结与依据使用自然中文。再次真实运行后，建议改为继续原练习对象，沿用已有 80 BPM，没有要求修改步骤或输出字段名。

预检还发现关闭代码签名的测试构建无法读取既有凭据。改用正常模拟器签名 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` 后，Keychain 查询状态为 0，凭据读取成功。[配置预检报告](2026-11-06-suggested-practice-live/configuration.json)只保存模型名、存在性与状态，不保存密钥或完整接口地址。

## 测试证据

| 结果包 | 结果 | 覆盖 |
| --- | --- | --- |
| `.scratch/suggested-practice-live-preflight-signed.xcresult` | 1 通过，0 失败、0 跳过 | 现有端点、模型、Keychain；不发请求 |
| `.scratch/suggested-practice-live-flow.xcresult` | 1 通过，0 失败、0 跳过 | 首轮真实完整流程；返回内容随后修正 |
| `.scratch/suggested-practice-live-verified.xcresult` | 24 通过，0 失败、0 跳过 | 18 项 Store、5 项输入/取消、1 项最终真实界面流程 |

结果均用 `xcresulttool get test-results summary` 核对。独立代码与 Swift 复查通过。首页展示前没有手填重点，测试未启用 `NextFocusFixture`。

新增的 `NextFocusLiveConfigurationTests` 与 `SuggestedPracticeLiveUITests` 通过 `GITA_NEXT_FOCUS_LIVE_TEST=1` 或 `TEST_RUNNER_GITA_NEXT_FOCUS_LIVE_TEST=1` 显式启用。默认回归跳过这些实测入口。复现时需保留上述模拟器签名设置，以及模拟器内已保存的模型配置和凭据。

本轮覆盖「明确练习对象、没有备注」的默认创建情形。结果来自模拟器与测试档案，未使用个人练习数据；真机未在本轮联调中验证。
