# Design: 记忆授权与管理 UI

> 上游：[`Gita-本地记忆知识库与AI-Skills-PRD.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆知识库与AI-Skills-PRD.md) P0-6 / P0-7 / §7.1 / §7.3；[`Gita-本地记忆知识库与AI-Skills-路线规划.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆知识库与AI-Skills-路线规划.md) Next X1 / X2；[`Gita-本地记忆与AI-Skills-用户体验及现状分析.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆与AI-Skills-用户体验及现状分析.md)。  
> 本文为 **Spec 3** 工程设计。Spec 1（Skills）与 Spec 2（Schema V6 只读注入）已落地。Spec 4（确定性 Task 回填 / AI 候选写入）另开文档。

**日期：** 2026-08-21  
**状态：** Draft — awaiting review  
**方案：** 方案 1 — 独立「AI 记忆」页 + 生成前授权门；Schema V7 三态同意；用户可手动添加 goal / preference。  
**成功标准：** 未选择的用户第一次点生成会看到说明，选完后请求发出；暂不之后三个入口都不再弹，请求体无 `BACKGROUND_MEMORY`；启用后用户手写的目标和偏好出现在对应 Skill 的 user 文本包装块中；设置里能开/关、看、改、删、清空；删除后的内容不再进入请求；关闭或读取失败时练习主流程不中断。

---

## 1. 背景与目标

Spec 2 已有隐藏默认 `LocalProfile`、`MemoryItem`、只读注入。生产里 `memoryConsent == false`，没有开关，正式路径不能写记忆。对真用户来说，只读管道等于关闭。

本轮补上：

1. 同意三态（未选择 / 已开 / 已关）。
2. 首次使用三个会读记忆的 AI 功能时弹出说明；选完立刻继续这次生成。
3. 设置 → AI 记忆：总开关、同一套隐私文案、列表、添加目标/偏好、编辑摘要、删除、清空。

不做：AI 候选写入、从 Task 回填、结果页「用了哪些记忆」、首页记忆卡片、下次练习建议、多 Profile UI、把三个 Skill 的 `memoryWritePolicy` 改成允许写入。

---

## 2. 产品与工程决策

| 项 | 选择 |
|---|---|
| 范围 | 授权 + 管理 UI。用户手动添加仅 `goal` / `preference` |
| 入口 | 设置「AI 接口」下加一行，推进独立页。首次生成弹同一套说明 |
| 同意 | 三态 `undecided` / `enabled` / `disabled`。「暂不启用」= `disabled`，不再弹 |
| 划掉弹窗 | 等同暂不，写入 `disabled` |
| 启用后 | 立刻继续这次生成；列表为空则请求与无记忆等价 |
| 迁移 | Schema V7 轻量。V6 `memoryConsent == false` → `undecided`；`true`（Debug 种子）→ `enabled` |
| 旧字段 | 保留 `memoryConsent: Bool`，不再作为门闩。写入同意时同步：enabled→true，其余→false |
| 注入 | `LiveMemoryContext` 仅在 `enabled` 时注入。`undecided` 与 `disabled` 都不注入 |
| Skill | 版本仍 `1.1.0`。冻结 Prompt 不变。`memoryWritePolicy` 仍 `.deny` |
| 产品写入 | 只允许用户 CRUD。不走 Skill 写入。保留 `upsertDebug` 给测试 / DEBUG 种子 |
| 删除 | 已有 `deletedAt` 软删。清空 = 当前 Profile 全部软删。关闭不删数据 |
| 关着时 | 列表仍可见、可删；不能添加；AI 不读 |
| Debug 种子 | 仍默认关。跑种子时同时把状态写成 `enabled` |
| `resetAll` | 本轮不改（仍不删 Profile / Memory）。批量删除只走记忆页「清空」 |
| Generator 协议 | 不变。授权门在 UI / Job 启动处，不进 Client |

---

## 3. 架构

```text
SettingsView (NavigationStack)
  → 行「AI 记忆」
      → AIMemorySettingsView
           ↕ MemoryStore (@Observable, @MainActor)
                ↕ MemoryRepository（显式 profileId）

PhotoPracticeSheet / Review 开始 / 视频诊断开始
  → MemoryConsentCoordinator.ensureDecided()
       undecided：弹出 MemoryConsentSheet
         「启用并继续」→ enabled → 继续本次生成
         「暂不启用」或划掉 → disabled → 继续本次生成（无记忆块）
       enabled / disabled：不弹，直接生成
  → 现有 Generator / Client
       LiveMemoryContext 仅 enabled 时拼 BACKGROUND_MEMORY
```

| 层 | 负责 | 不负责 |
|---|---|---|
| `GitaSchemaV7` | `LocalProfile.memoryConsentState` | 改 MemoryItem 结构、Profile `@Relationship` |
| `PracticeStore.prepare()` | 把旧 Bool 回填成三态（若 state 仍空） | 记忆列表 UI |
| `MemoryRepository` | fetch；用户 upsert / 改摘要 / 软删 / 清空；写同意 | AI 候选、改 Prompt |
| `MemoryStore` | 给设置页的列表与操作、暴露同意状态 | SwiftData 细节泄漏给 View |
| `MemoryConsentCoordinator` | 未选择时请求 UI 弹窗并落盘 | 发 HTTP |
| `LiveMemoryContext` | `enabled` 才 fetch | 弹窗 |
| Client / Generator | 与 Spec 2 相同 | 同意 UI |
| `AIMemorySettingsView` | 开关、文案、列表、表单 | 直接 `ModelContext.fetch` |

约束：

- View 不直接 fetch `MemoryItem` / `LocalProfile`。
- 整批复盘 / 多条录音只问一次，不问每条。
- 三个生成入口共用同一套文案与同一 coordinator。

---

## 4. Schema V7

复制 `GitaSchemaV6` 全部模型到 `GitaSchemaV7`。只改 `LocalProfile`：

```swift
var memoryConsent: Bool           // 保留，默认 false；不再当门闩
var memoryConsentState: String = ""  // "", "undecided", "enabled", "disabled"
```

- `versionIdentifier = Schema.Version(7, 0, 0)`。
- `GitaMigrationPlan` 增加 lightweight `MigrateV6toV7`。新列默认 `""`。不使用 `willDestroy`。
- 类型别名切到 V7。`GitaSchemaV6` 留给迁移测试写旧库。
- `PracticeStore.prepare()` 在确保 Profile 之后：若 `memoryConsentState.isEmpty`，则 `memoryConsent ? "enabled" : "undecided"`，并 `save`。
- Swift 枚举（非 SwiftData 模型）：

```swift
enum MemoryConsentState: String {
    case undecided
    case enabled
    case disabled
}
```

`LocalProfile` 提供 `var consent: MemoryConsentState` 计算属性：raw 无法识别或为空时按 `undecided` 读；set 时写 raw，并同步 `memoryConsent = (newValue == .enabled)`。

Debug 种子：`profile.consent = .enabled` 后再 upsert。

---

## 5. MemoryRepository

在现有 `fetch` / `upsertDebug` / `save` 上增加产品路径（均要求非空 `profileId`，否则 `StoreError.invalidInput`）：

```swift
func upsertUser(profileId: String, kind: MemoryScope, summaryText: String) throws -> MemoryItem
func updateSummary(profileId: String, id: String, summaryText: String) throws
func softDelete(profileId: String, id: String) throws
func softDeleteAll(profileId: String) throws
func setConsent(profileId: String, _ state: MemoryConsentState) throws
```

规则：

- `upsertUser`：`kind` 只允许 `.goal` / `.preference`，否则 `invalidInput`。`summaryText` trim 后非空且 `count <= 120`，否则 `invalidInput`。新建 `key = "user.\(kind.rawValue).\(UUID)"`，`sourceType = "user"`，`sourceId = ""`，`confidence = 1`，`importance = 0.8`，`expiresAt = nil`，`valueJSON = ""`。
- `updateSummary`：只改匹配 `(profileId, id, deletedAt == nil)` 的 `summaryText` + `updatedAt`。不改 `key` / `kind`。找不到 → `invalidInput`。字数规则同添加。
- `softDelete` / `softDeleteAll`：写 `deletedAt = now`。已删的忽略。清空只动当前 `profileId`。
- `setConsent`：更新该 Profile 的 `consent`（及同步 Bool）+ `updatedAt`。找不到活跃 Profile → `invalidInput`。
- 用户路径不调用 `upsertDebug`。`upsertDebug` 仍可覆盖任意 kind（测试 / 种子）。

`fetch` 行为不变（软删、过期、未知 kind、scope、关键词加权）。

---

## 6. MemoryStore

`@MainActor @Observable final class MemoryStore`。由 `foxgitaApp` 用同一个 `SwiftDataMemoryRepository` 构造，`.environment(memoryStore)`。

```swift
private(set) var consent: MemoryConsentState
private(set) var items: [MemoryItem]  // 未删除，当前 Profile
private(set) var lastError: StoreError?
```

- `reload()`：读活跃 Profile 的 consent + `fetch(scopes: [.goal, .preference, .ability, .fact, .summary], matching: "")`（`MemoryScope` 目前不是 `CaseIterable`）。失败设 `lastError`，不抛到 View。
- `setConsent(_:)`、`add(kind:summary:)`、`updateSummary(id:summary:)`、`delete(id:)`、`clearAll()`：调 Repository + `save` + `reload`。失败 toast / `lastError`，状态不变。
- `add` 在 `consent != .enabled` 时直接 `invalidInput`（关着不能添加）。
- `prepare()` 回填同意之后调用一次 `memoryStore.reload()`（或 App `onAppear` 里在 `store.prepare()` 之后）。

`PracticeStore` 不增加记忆列表 API。`LiveMemoryContext` 继续自己读 Profile / Repository，不依赖 Store，避免生成路径和设置页抢状态。

---

## 7. 授权门

SwiftUI 修饰符 `memoryConsentGate`（内部用 `MemoryConsentCoordinator` + `MemoryStore`），三个入口自己挂，不在 Client / Generator 里弹窗。

```swift
func ensureDecided() async -> ConsentGateResult
enum ConsentGateResult { case proceed, aborted }
```

流程：

1. 调用方在 Generator **之前** `await ensureDecided()`。
2. `enabled` / `disabled` → `.proceed`，不弹。
3. `undecided` → 修饰符 present `MemoryConsentSheet`；「启用并继续」/「暂不启用」/划掉后 `setConsent`；成功 → `.proceed`；失败 → `.aborted`（toast，**不发**这次 AI）。
4. 仅 `.proceed` 才生成。

挂载点：

1. `PhotoPracticeSheet.generate`
2. 用户开始复盘的动作（`ReviewJobRunner` 开跑前）。一批录音只问一次。
3. 用户开始视频诊断的动作。

Sheet 与设置页共用文案常量（见 §9）。按钮：「启用并继续」「暂不启用」。

---

## 8. UI

### 8.1 设置入口

`SettingsView` 根包 `NavigationStack`（当前设置 Tab 没有栈）。「AI 接口」分组末尾加一行「AI 记忆」，副文案「Gita 记住的目标和偏好」，`NavigationLink` 到 `AIMemorySettingsView`。

### 8.2 AI 记忆页

- 总开关：绑定「是否 enabled」。`undecided` 时开关显示关闭；打开 → `enabled`；从 `enabled` 关掉 → `disabled`。`undecided` 下开关已是关，用户不能靠开关写成 `disabled`（靠首次说明或之后再关）。
- 开关下四条隐私说明（§9），只读。
- 列表分组：`目标`（goal）、`偏好`（preference）。若存在 `ability` / `fact` / `summary`（Debug 种子），只读分组展示，不可从本页新建这三类。
- 每条：`summaryText`、来源（`user` →「你添加的」；`debug_seed` →「调试种子」；其它 raw）、相对更新时间。
- 添加：kind 二选一 + 摘要。编辑：只改摘要。删除 / 清空：系统 `.alert` 确认。
- 空 + enabled：「还没有记忆，添加一条目标或偏好」。
- 非 enabled：列表仍在；隐藏添加；可删。

沿用 `GitaTheme` / `GitaFont`，中文文案进 String Catalog。

### 8.3 首次说明

`.sheet`，不可通过生成路径绕过。三个入口同一 `MemoryConsentSheet`。

---

## 9. 冻结文案

设置页与首次 Sheet 使用同一组句子，实现时放进一个常量（或 LocalizedStringKey 集合），测试可断言包含：

1. 记忆保存在这台设备上。
2. 若启用以获得更贴合的建议，本次只会把少量相关文字发给你在设置里配置的模型服务。
3. 不会因为开启记忆而自动上传历史录音或视频；只有当前这次功能选中的内容会参与请求。
4. 你可以随时在设置里关闭或清除记忆。

按钮：「启用并继续」「暂不启用」。导航标题：「AI 记忆」。

---

## 10. 错误与降级

| 情况 | 行为 |
|---|---|
| 同意写入失败 | toast，状态仍 undecided，**不发**本次 AI |
| 列表加载失败 | 记忆页内错误 + 重试；设置其它项不受影响 |
| 添加/编辑/删除失败 | toast，列表保持原样 |
| 记忆读取失败（生成中） | 与 Spec 2 相同：注入 `""`，生成继续 |
| 未配置 API | 现有 Generator 错误，与同意无关 |
| 关闭或未选择 | 不注入；功能可用 |

不新增 `VisionPracticeError` / `MediaReviewGeneratorError` case。

---

## 11. 测试

真行为，不把 Repository 换成空 mock 来「证明」CRUD。

| 用例 | 断言 |
|---|---|
| V6→V7 迁移 | 任务 / Session / 记忆还在。旧 `memoryConsent false` → `undecided`；`true` → `enabled` |
| 同意门 | undecided 才需要决定；enabled 后这次生成可走；disabled 后请求无 `BACKGROUND_MEMORY`；之后 `ensureDecided` 不再要求 UI |
| 划掉 | 结果为 `disabled` |
| 注入 | 仅 `enabled` + 有条目时 user 文本含包装块；system prompt 仍冻结 |
| upsertUser | 只能 goal/preference；空摘要 / 超 120 失败；key 前缀 `user.goal.` / `user.preference.`；`sourceType == "user"` |
| updateSummary | 摘要变、key/kind 不变 |
| 软删 / 清空 | fetch 不到；注入不含该条；其它 Profile 不受影响 |
| 关着添加 | `add` 失败 |
| 双 Profile | 列表与注入零泄漏 |
| 回归 | 三个 Client 冻结 prompt 快照仍过；默认 Empty 无记忆块 |
| Debug 种子 | 写入后 consent 为 `enabled` |

UI 可用 View 层对 Store 的轻量测试 + 现有 `foxgitaTests`；不强制新 UITest。

xcodebuild 目的地保持 iPhone 17（见 `docs/TEST_PLAN_CLI.md`）。

---

## 12. 文件地图

| 路径 | 动作 |
|---|---|
| `foxgita/Models/SchemaV7.swift` | 新建。V6 副本 + `memoryConsentState` |
| `foxgita/Models/Models.swift` | 类型别名 V7；migration 加 V6→V7 |
| `foxgita/foxgitaApp.swift` | Schema V7；注入 `MemoryStore` |
| `foxgita/ContentView.swift` | preview 模型含 V7 类型 |
| `foxgita/Services/MemoryRepository.swift` | 产品 CRUD + `setConsent` |
| `foxgita/Services/MemoryStore.swift` | 新建 |
| `foxgita/Services/MemoryConsentCoordinator.swift` | 新建 |
| `foxgita/Services/MemoryContextProviding.swift` | 门闩改为 `consent == .enabled` |
| `foxgita/Services/MemoryDebugSeeder.swift` | 种子时写 `.enabled` |
| `foxgita/Services/PracticeStore.swift` | `prepare` 回填空的 `memoryConsentState` |
| `foxgita/Features/Settings/SettingsView.swift` | NavigationStack + 入口行 |
| `foxgita/Features/Settings/AIMemorySettingsView.swift` | 新建 |
| `foxgita/Features/Settings/MemoryConsentSheet.swift` | 新建 |
| `foxgita/Features/Practice/PhotoPracticeSheet.swift` | 生成前 ensureDecided |
| 复盘 / 视频开始处 | 开跑前 ensureDecided（具体文件以现有按钮为准） |
| `foxgitaTests/MigrationTests.swift` | V6→V7 |
| `foxgitaTests/MemoryRepositoryTests.swift` | 用户 CRUD / 同意 |
| `foxgitaTests/MemoryStoreTests.swift` | 关着不能添加等 |
| `foxgitaTests/MemoryConsentTests.swift` | 三态门闩 + Live 注入 |
| `foxgitaTests/MemoryContextTests.swift` | consent 改读 state |
| `docs/TECHNICAL.md` / `docs/TEST_PLAN_CLI.md` | 本轮末尾更新 |

新文件仍由 `PBXFileSystemSynchronizedRootGroup` 收录，不改 `project.pbxproj`。

---

## 13. 明确不做

- AI 候选、`memoryWritePolicy` 放开、多 Session 证据。
- 从 Task / 练习偏好回填确定性记忆。
- 结果页记忆引用、首页「Gita 记得我」卡片。
- `practice.next_session` / 周总结。
- 多 Profile 切换、云同步、向量检索。
- 自定义 migration `willDestroy`。
- 改 Generator 协议或冻结 system / user 主文案（只允许在 user 末尾继续拼包装块）。

---

## 14. 实施顺序（供计划拆任务）

1. Schema V7 + 回填 + 迁移测试。
2. Repository 用户 CRUD + setConsent。
3. LiveMemoryContext 改读三态；MemoryContextTests。
4. MemoryStore。
5. 设置入口 + AI 记忆页。
6. Consent sheet + 三个生成入口接线。
7. Debug seeder 写 enabled；文档。
