# Gita AI Platform：Task 7–11 剩余迁移方案

**状态：** 已确认  
**目标：** 将 `practice.next_session`、`practice.plan.from_image`、`practice.review.media`、`practice.diagnose.video` 全部迁移到共享 AI Platform，并在等价验收后删除四套旧 Client 编排。

## 1. 已完成基线

Task 1–6 已提供领域中立契约、执行状态机、受限 Context Fetching/Fencing、Snapshot/SeenSet、Provenance 与审批门禁、Prompt Cache 三断点、MessagesRuntime、Artifact 校验、Extension Registry 和 AgentOrchestrator。剩余工作不得绕过这些边界。

## 2. 已确认的产品与架构决策

- 四个 AI Recipe 独立渐进迁移，顺序为：下一次练习 → 图片计划 → 媒体复盘 → 视频诊断。
- 每个 Recipe 使用四态迁移开关：`legacy → internalPlatform → platformDefault → removed`；普通用户不看到开关。
- 不在线上对同一请求双调用模型；等价比较使用 Fixture、录制响应和内部样本。
- Practice Draft 必须执行 `Artifact → Preview → Host Approval → Apply`。任何编辑都改变草稿 Hash，并使旧审批失效。
- Review Result 是 Recording 的派生分析，校验通过后可自动落库；Candidate Memory 是长期画像候选，必须在结果页面就地批准。
- 忽略 Candidate Memory 时，记录“证据 + 语义”的拒绝，避免重复提示；新证据可形成新候选。
- Regenerate 创建新 Invocation；旧 Invocation 标为 `regenerated` 并关联后继 Invocation。
- 同一 Recording 重跑后只展示最新 Review Result，但保留历次 Invocation/Artifact 审计链。
- V17 历史记录的新字段使用 `legacy/unknown/nil`，不得把“未采集”伪装成零值。

## 3. 目标业务链路

```text
Feature UI
  → Recipe Runner
  → AgentOrchestrator
  → scoped ContextSnapshot + SeenSet
  → PromptAssembler (BP1/BP2 后才进入动态数据)
  → MessagesRuntime
  → typed AI Artifact
  → domain validator + ProvenanceGate
  ├─ Practice Draft → Preview → Host Approval → Apply → PracticeItem
  └─ Review Result → Recording
                     └─ Candidate Memory Draft → Host Approval → Memory
```

## 4. Task 7：Schema V18 与可观测性

### 交付

- V17→V18 迁移，保留历史字段；缺失数据表达为 `legacy/unknown/nil`。
- Invocation 记录 runtime、execution state、BP fingerprints、input/output/cache token、refusal/fallback、snapshot/artifact/business-object ID 与时间戳。
- 形成 `Invocation → Artifact → Business Object → Invocation Outcome` 关联。
- `regenerated` 记录后继 Invocation ID。
- Debug 输出只包含安全元数据，不得包含 API Key、Bearer、原始 Prompt、原始媒体、完整供应商响应或绝对路径。

### 完成门槛

- 独立 V17→V18 Fixture 验证数据保留和 unknown 语义。
- Store API 覆盖 started/completed/artifact/business outcome/regenerated。
- Redaction 测试覆盖所有禁止持久化内容。

## 5. Task 8：Extension 与下一次练习

### 交付

- `GitaPracticeExtension` 精确声明四个 Recipe，旧 `SkillDefinition` 只做单一来源兼容映射。
- `PracticeContextReader` 将 Gita 数据适配为受限资源；保持现有 memory policy。
- `PracticePlanArtifactValidator` 统一预算、步骤、分类与归一化规则。
- `NextSessionGenerator` 依赖 `PracticePlanRunning`，不再自行构造 Client/Transport。
- 保持“时长 → 生成 → 可编辑预览 → 加入今日练习”的 UI、文案和失败提示不变。
- 编辑后重新计算 Draft Hash；批准后写入并关联 Invocation/Artifact/PracticeItem。

### 完成门槛

- 新旧业务不变量、错误文案、预算归一化和 citation 行为等价。
- `internalPlatform` 验证通过后进入 `platformDefault`。

## 6. Task 9：图片计划与强制预览

### 交付

- 图片作为 invocation-scoped Resource；只传字节，不暴露本地路径。
- `ImageStepGenerator` 依赖 `ImagePlanRunning` 并复用计划 Validator。
- 当前“生成后自动创建 PracticeItem”改为 pending Practice Draft。
- 用户可编辑后明确批准；关闭记为 `abandoned` 且零写入；重新生成产生新 Invocation。

### 完成门槛

- 未批准、关闭、生成失败均不得创建任务。
- 批准只写入一次，并关联 Invocation/Artifact/PracticeItem。

## 7. Task 10：媒体复盘与视频诊断

### 交付

- 两个 Recipe 共用平台执行机制，但保持独立 Artifact/Validator。
- 校验时间范围、证据文本、最多五条 finding；没有确定性音频证据时移除伪精确音高结论。
- Review Result 校验通过后自动写入 Recording；失败状态可见并可手动重试，原始录音和手动记录不受影响。
- 重跑替换当前展示结果，历史 Invocation/Artifact 保留。
- Candidate Memory 单独 staged，在 Review Result/Video Diagnosis 页面展示“记住/忽略”；批准后才持久化。

### 完成门槛

- 越界证据、无来源引用和不支持的精确结论均被代码拒绝或降级。
- 自动落库 Review Result 不会隐式写入 Candidate Memory。

## 8. Task 11：切换与清理

### 删除旧 Client 的硬门槛

每个 Recipe 必须同时满足：聚焦测试通过、业务不变量等价、写入结果等价、失败降级可用、用户文案保持、内部灰度通过、生产入口已切到平台。

满足全部门槛后：

1. 状态切到 `platformDefault` 并观察；
2. 确认无旧生产入口；
3. 删除四套旧 Client 编排；
4. 状态切到 `removed`；
5. 保留版本控制回滚，不保留隐藏双实现。

最终依赖装配只构造一套 Registry、Context Reader、MessagesRuntime、AgentOrchestrator 和 Gita Runner。边界测试必须证明四个 Generator 只依赖 Recipe Runner。

## 9. 质量与指标

- 可靠性：调用成功率、Artifact 校验通过率、P95、后台落库成功率。
- 安全性：各 Gate 拒绝率/原因、未授权资源与重放均为零容忍。
- 成本：BP1/BP2 cache-read token 比例、每个 accepted outcome 的 token 成本。
- 业务采用：accepted/abandoned/regenerated、Candidate Memory 批准率。
- 降级：AI 失败后手动练习、录音和复盘继续可用。

## 10. 已知基线与执行纪律

当前全量测试存在既有 SwiftData `GitaSchemaV17` 模型强转崩溃。每个 Task 必须保留聚焦通过证据；最终合并前应修复或隔离该基线问题，并清晰区分既有失败与本分支回归。

