# Gita AI Recipe Migration Specification

## Problem Statement

Gita 的下一次练习、图片计划、媒体复盘和视频诊断分别维护模型调用、上下文拼装、结果解析、错误处理与写入逻辑。用户因此面对不一致的安全边界、预览方式和失败体验：图片计划可能在用户确认前创建任务，复盘结果可能隐式改变长期记忆，AI 建议也缺少从证据到业务结果的统一追踪。

Task 1–6 已建立共享 AI Platform，但四个 AI Recipe 尚未迁移，调用审计与业务结果关联也尚未完成。只要旧 Client 仍是生产入口，平台的 Context Fencing、Provenance、Host Approval、Prompt Caching 和统一编排就无法真正转化为用户价值。

## Solution

完成 Schema V18 与调用可观测性，并按照下一次练习、图片计划、媒体复盘、视频诊断的顺序，将四个 AI Recipe 渐进迁移到共享 AgentOrchestrator 和 MessagesRuntime。

Practice Draft 在写入练习数据前必须允许预览和编辑，并通过绑定最终草稿 Hash 的 Host Approval。Review Result 作为 Recording 的派生分析可以在校验后自动落库；Candidate Memory 必须作为独立草稿在结果页面由用户选择“记住”或“忽略”。每个 Recipe 独立经历 `legacy → internalPlatform → platformDefault → removed`，完成行为等价与内部验证后，才删除对应旧 Client。

## User Stories

1. 作为练习用户，我希望下一次练习建议继续使用熟悉的时长、生成、预览和确认流程，从而无需重新学习界面。
2. 作为练习用户，我希望 AI 生成的 Practice Draft 可以在保存前编辑，从而最终计划符合我的真实意图。
3. 作为练习用户，我希望只有点击明确的确认按钮后才创建 PracticeItem，从而避免 AI 擅自修改练习安排。
4. 作为练习用户，我希望编辑草稿后批准的是最新内容，从而不会授权已经过期的草稿版本。
5. 作为练习用户，我希望关闭未批准的草稿不会创建任何任务，从而能够放心试用 AI。
6. 作为练习用户，我希望重新生成产生独立结果，从而可以比较后选择更合适的建议。
7. 作为图片计划用户，我希望选择的图片只用于本次请求，从而不会扩大 AI 可访问的数据范围。
8. 作为图片计划用户，我希望应用不记录图片绝对路径或原始图片内容，从而降低隐私暴露风险。
9. 作为图片计划用户，我希望生成后先看到可编辑预览，而不是直接进入已创建的练习任务。
10. 作为复盘用户，我希望媒体分析完成后自动出现在对应 Recording 上，从而保留后台生成的便利性。
11. 作为复盘用户，我希望失败状态清楚可见并可以手动重试，从而无需重新导入录音。
12. 作为复盘用户，我希望 AI 失败时原始录音、播放和手动记录仍然可用。
13. 作为视频诊断用户，我希望诊断时间范围不会超出视频实际时长，从而避免虚假定位。
14. 作为视频诊断用户，我希望没有音频证据时 AI 不给出伪精确的音高数值，从而获得更可信的反馈。
15. 作为视频诊断用户，我希望当前页面只展示最新诊断，同时系统保留历史生成来源以便审计。
16. 作为记忆功能用户，我希望 Review Result 不会自动改变我的长期画像。
17. 作为记忆功能用户，我希望在看到对应证据时决定是否“记住”Candidate Memory。
18. 作为记忆功能用户，我希望忽略同一证据和语义后不再反复被提示。
19. 作为记忆功能用户，我希望新练习证据仍可形成新的 Candidate Memory。
20. 作为隐私敏感用户，我希望每次 AI 调用只读取当前授权的项目、任务、记忆和媒体资源。
21. 作为用户，我希望 AI 建议引用的资源确实来自本次调用读取的证据。
22. 作为用户，我希望聊天文字不能被系统误认为数据写入批准。
23. 作为用户，我希望一次批准不能被重复使用，从而避免重复创建或重复写入。
24. 作为用户，我希望 AI 功能失败时仍能继续手动练习、录音和复盘。
25. 作为产品运营者，我希望分别查看四个 AI Recipe 的成功率、耗时、采用率和失败原因。
26. 作为产品运营者，我希望查看 Practice Draft 的接受、放弃和重新生成比例，从而判断建议价值。
27. 作为产品运营者，我希望查看 Candidate Memory 批准率，从而判断用户对长期画像建议的信任程度。
28. 作为成本负责人，我希望知道 BP1/BP2 的缓存读取 token 比例和单次有效采用成本。
29. 作为安全负责人，我希望 Gate 拒绝有结构化原因，从而区分越权、来源、格式与审批问题。
30. 作为开发者，我希望四个功能通过同一 Recipe Runner 接缝执行，从而不再复制 Client 编排。
31. 作为开发者，我希望新增 Recipe 只需提供 Context Policy、Artifact Decoder、Validator 和 Presenter。
32. 作为开发者，我希望模型供应商 DTO 不越过 Runtime 边界，从而保持业务代码与供应商无关。
33. 作为开发者，我希望旧 Invocation 的未知指标保持 unknown，而不是被错误解释为零。
34. 作为开发者，我希望能从 Invocation 追踪到 Artifact 和最终业务对象，从而定位线上问题。
35. 作为开发者，我希望每个 Recipe 可以独立灰度和回滚，从而降低一次性迁移风险。
36. 作为开发者，我希望内部等价验证不重复发送线上模型请求，从而避免双倍成本、隐私暴露和副作用。
37. 作为维护者，我希望所有 Recipe 完成等价验收后删除旧 Client，从而避免两套规则长期漂移。

## Implementation Decisions

- Schema V18 扩展 Invocation，记录 runtime、execution state、Prompt fingerprints、input/output/cache token、refusal/fallback、Context Snapshot、Artifact、业务对象和生命周期时间戳。
- V17 历史记录保持原数据；无法得知的新字段使用 `legacy`、`unknown` 或 `nil`。未采集数据不能回填成零。
- 持久化与调试输出禁止包含 API Key、Authorization、原始 Prompt、原始媒体、完整供应商响应和本地绝对路径。
- Invocation、AI Artifact、业务对象和 Invocation Outcome 形成可追踪链；Outcome 包括 accepted、abandoned、regenerated 和 failed。
- Regenerate 创建新 Invocation，旧 Invocation 记录 regenerated 并关联后继 Invocation。
- GitaPracticeExtension 精确声明四个 Phase 1 AI Recipe；旧 Skill 定义在迁移期间只充当同一来源的兼容门面。
- 下一次练习和图片计划共享 Practice Draft 的领域校验，包括预算、步骤、分类和归一化。
- 下一次练习保持现有用户流程和可见文案，只替换底层执行路径。
- 图片作为 invocation-scoped Resource 读取；媒体字节与文本 Prompt 分离，绝对路径不进入快照、日志或持久化。
- Practice Draft 的任何编辑都会产生新的内容 Hash；Host Approval 必须绑定当前 Hash、用户、会话、草稿和过期时间。
- Review Result 经结构、证据范围与 Provenance 校验后自动关联 Recording，不要求 Mutation Approval。
- Candidate Memory 与 Review Result 分离，必须经过现有 consent 规则和 MutationGate 后才能写入长期记忆。
- 被忽略的 Candidate Memory 以证据和语义为键记录拒绝；相同候选不再提示，新证据不受阻止。
- 同一 Recording 重跑时替换当前展示的 Review Result，但保留历次 Invocation 和 Artifact 关联。
- 视频 finding 满足 `0 ≤ start < end ≤ duration`、证据非空、最多五条；没有确定性音频证据时移除伪精确音高声明。
- 后台失败保留可见状态与手动重试入口，不删除或破坏 Recording。
- 每个 Recipe 使用 `legacy → internalPlatform → platformDefault → removed` 生命周期；开关仅内部可见。
- 不使用线上影子双调用。等价验证使用确定性 Fixture、录制响应和内部样本。
- 仅在四个 Recipe 的业务不变量、写入、错误降级、用户文案、聚焦测试和内部验证通过后删除旧 Client。
- Phase 1 只有 MessagesRuntime；Agent SDK、Managed Agents 和 BP3 均不启用。

## Testing Decisions

- 主测试接缝是四个 Recipe Runner 的外部行为；测试输入、AI Artifact、用户可见结果、写入、Host Approval、Invocation Outcome 与失败降级，不断言内部调用步骤。
- 只在必须验证不可绕过边界时保留 Schema Migration、Gate、Context Fencing、Prompt Assembly、Runtime 和领域 Validator 专项测试。
- 下一次练习验证预算/步骤归一化、citation、现有错误文案、可编辑预览与批准后单次写入。
- 图片计划验证生成后零写入、关闭后 abandoned、编辑导致旧批准失效、批准后单次创建与资源隐私。
- 媒体复盘验证 Review Result 自动落库、失败可重试、Candidate Memory 不自动保存以及记住/忽略行为。
- 视频诊断验证时间范围、finding 上限、证据要求、无音频时的精度降级、重跑替换当前结果。
- Invocation 测试验证 V17→V18 数据保留、unknown 语义、redaction、Artifact/业务对象关联和 regenerated 后继关系。
- 架构边界测试验证四个生产 Generator 只依赖 Recipe Runner，不直接构造 AITransport 或旧 Client。
- Feature Flag 状态测试验证每个阶段只有一个生产执行路径，且不存在同请求双模型调用。
- 复用现有 Generator、Client、Draft、ReviewJobRunner、PracticeStore、AICandidateSync、Migration 与 Invocation Store 测试作为等价先例。
- 好的测试只观察外部行为和持久化结果；避免源代码文本扫描和对私有实现顺序的脆弱断言。

## Out of Scope

- Agent SDK 与 Managed Agents 适配器。
- 自主多步骤 Agent 循环、通用聊天界面和 Extension 市场。
- 远程 Feature Flag 服务；Phase 1 使用内部本地配置。
- 线上新旧链路双模型调用。
- 新增周报、反思或其他新 AI Recipe。
- 缓存最终个性化模型答案。
- 用模型判断替代确定性练习规则。
- 自动清理 Invocation 的长期保留策略；本期只建立隐私边界和数据关联。
- 与本迁移无关的 SwiftData 基线修复，但最终合并验证必须明确隔离或解决该问题。

## Further Notes

- 迁移顺序固定为：Schema V18 → 下一次练习 → 图片计划 → 媒体复盘 → 视频诊断 → 旧 Client 清理。
- 成功指标同时覆盖可靠性、安全性、成本和业务采用，不能只看模型请求成功率。
- 当前全量测试存在既有 SwiftData 模型强转崩溃；每个任务必须保留聚焦测试证据，并在最终报告中区分既有失败和新回归。
- 相关领域术语与边界以项目 CONTEXT 和 AI 迁移 ADR 为准。
