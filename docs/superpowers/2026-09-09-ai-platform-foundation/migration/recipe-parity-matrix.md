# 四个 AI Recipe 迁移与等价验收矩阵

| Recipe | 当前入口 | 目标 Artifact | Context/Memory | 写入与批准 | 失败降级 | 迁移验收重点 |
|---|---|---|---|---|---|---|
| `practice.next_session` | `NextSessionSheet` | Practice Draft | 目标、偏好、能力；memory `.deny` | 可编辑预览；Host Approval 后创建 PracticeItem | 保留现有错误文案，手动创建可用 | UI/文案零变化；预算与步骤归一化等价；Invocation/Artifact/Item 关联 |
| `practice.plan.from_image` | `PhotoPracticeSheet` | Practice Draft | 选中图片为 invocation-scoped Resource；memory `.deny` | 禁止自动提交；编辑并批准后创建 | 关闭=abandoned、零写入 | 不保存路径/原图；未批准不写；批准只写一次 |
| `practice.review.media` | `ReviewGenerationSheet` | Review Result + 可选 Candidate Memory | Recording/媒体资源；memory `.candidates` | Review Result 自动关联 Recording；Memory 单独批准 | failed 可见可重试，录音不受影响 | 音视频证据一致；结果与记忆解耦；重跑保留审计链 |
| `practice.diagnose.video` | `ReviewGenerationSheet` / `VideoDiagnosisView` | Video Review Result + 可选 Candidate Memory | 视频、duration、确定性证据；memory `.candidates` | Result 自动落库；Memory 就地批准 | failed 可见可重试，原视频可查看 | 时间范围、最多五条、Provenance、无音频时移除伪精确音高 |

## 通用等价检查

| 维度 | 必须满足 |
|---|---|
| 输入 | 相同用户选择、项目/任务范围、同等媒体预处理 |
| Prompt | 现有用户可见 Recipe 文案保持；动态数据仅位于 BP2 后 |
| 输出 | 允许文本差异，但结构、边界和业务不变量一致 |
| 安全 | 每次重新校验 scope、ownership、SeenSet、Provenance 与 approval |
| 写入 | Practice Draft 必须批准；Review Result 可自动落库；Candidate Memory 必须批准 |
| Outcome | accepted、abandoned、regenerated、failed 及后继 Invocation 可追踪 |
| 错误 | unauthorized、timeout、format、cancelled 与 legacy 用户文案兼容 |
| 降级 | AI 失败不得阻断手动练习、录音、播放、记录和复盘 |
| 隐私 | 不持久化密钥、原始 Prompt/媒体/响应和绝对路径 |
| 成本 | 记录 token/cache 指标，不缓存个性化最终答案 |

## Feature Flag 状态门

| 状态 | 允许行为 | 进入条件 |
|---|---|---|
| `legacy` | 仅旧链路 | 新 Runner 尚未通过聚焦测试 |
| `internalPlatform` | 内部用户走平台；不双调用模型 | Fixture 等价与安全测试通过 |
| `platformDefault` | 正式入口默认走平台；旧实现仅待删除 | Recipe 全部等价门槛和内部灰度通过 |
| `removed` | 旧 Client 与装配删除 | 无旧生产入口且 Task 11 边界/回归验证通过 |

## Candidate Memory 验收

- 页面同时展示证据、候选语义和“记住/忽略”。
- “记住”签发绑定当前候选 Hash 的 Host Approval；消费后不可重放。
- “忽略”保存证据+语义拒绝记录，同一候选不重复提示；新证据允许新候选。
- Review Result 的保存不得隐式触发记忆写入。

