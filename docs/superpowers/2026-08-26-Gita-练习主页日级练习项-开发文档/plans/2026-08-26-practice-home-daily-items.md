# Gita 练习主页日级练习项 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将练习主页的数据源收敛为“按自然日存在的实际练习项”，保留按日期查看、日历和打卡状态，取消主页对 Draft、Session、练习次数和跨天练习任务的依赖。

**Architecture:** 在 SwiftData Schema V9 新增 `PracticeItem`，作为主页、详情、计时和统计的唯一新写入模型；时间采用绝对值覆盖保存，日期采用创建时固定的 `practiceDayKey`。旧 `TaskItem`、`PracticeSession` 暂时保留为只读兼容数据，不进入新练习链路。视图只消费按日期分组的 `PracticeItemSnapshot`，从同一集合派生列表、当日总时长、日历标记和打卡状态。

**Tech Stack:** Swift 6、SwiftUI、SwiftData、Swift Testing、Xcode 26 / iOS Simulator

**Spec:** [docs/superpowers/specs/2026-08-26-Gita-练习主页日级练习项-开发文档.md](../specs/2026-08-26-Gita-练习主页日级练习项-开发文档.md)

## Global Constraints

- `PracticeItem` 表示某一天真实发生的一项练习；创建后 `practiceDayKey` 不因跨夜、再次打开或再次保存而改变。
- 新流程不创建 `PracticeSession`、Draft 或可跨天继续的 `TaskItem`。
- 不展示、不计算练习次数；“保存两次”仍是同一条练习项。
- 练习时长只存于 `PracticeItem.durationSeconds`，保存采用绝对值覆盖，禁止累加。
- 日期总时长、日历打卡和统计必须由同一批有效 `PracticeItem` 派生。
- “练习项目”属于下一份产品文档，本计划不得引入 Project 或跨天聚合。
- 不修改 `project.pbxproj`；不要覆盖用户已有的 `foxgita/Localizable.xcstrings` 变更。
- 命令工作目录均为 `/Users/haizei/work/AI/program/gita/foxgita`。

---

### Task 1: 固化日期键和日级练习项纯规则

**Files:**
- Create: `foxgita/Features/Practice/PracticeDayKey.swift`
- Create: `foxgita/Features/Practice/PracticeItemRules.swift`
- Create: `foxgitaTests/PracticeItemRulesTests.swift`

**Interfaces:**

```swift
enum PracticeDayKey {
    static func make(from date: Date, calendar: Calendar) -> String
}

struct PracticeItemSnapshot: Equatable, Identifiable {
    let id: UUID
    let practiceDayKey: String
    let createdAt: Date
    let title: String
    let durationSeconds: Int
    let isDeleted: Bool
}

enum PracticeItemRules {
    static func items(for dayKey: String, in items: [PracticeItemSnapshot]) -> [PracticeItemSnapshot]
    static func totalDuration(for dayKey: String, in items: [PracticeItemSnapshot]) -> Int
    static func checkedInDayKeys(in items: [PracticeItemSnapshot]) -> Set<String>
}
```

- [ ] **Step 1: Write failing date-key tests**

  固定测试时区，覆盖同一天不同时间得到相同 key、跨午夜得到不同 key。

- [ ] **Step 2: Run and verify RED**

  ```bash
  xcodebuild -project foxgita.xcodeproj -scheme foxgita \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:foxgitaTests/PracticeItemRulesTests test
  ```

  Expected: FAIL because the new types do not exist.

- [ ] **Step 3: Implement the smallest date-key formatter**

  使用调用方传入的 `Calendar` 和本地年月日生成固定 `yyyy-MM-dd`；不要用 UTC 截断或共享 `DateFormatter`。

- [ ] **Step 4: Add failing derivation tests**

  断言删除项被排除、日期严格匹配、列表按 `createdAt` 倒序、负时长按 0 处理、零时长有效项仍算打卡。

- [ ] **Step 5: Implement rules and verify GREEN**

  所有逻辑只读取 `[PracticeItemSnapshot]`，不读取 Session、Task 或次数。

- [ ] **Step 6: Commit**

  ```bash
  git add foxgita/Features/Practice/PracticeDayKey.swift foxgita/Features/Practice/PracticeItemRules.swift foxgitaTests/PracticeItemRulesTests.swift
  git commit -m "feat: define daily practice item rules"
  ```

---

### Task 2: 新增 SwiftData Schema V9

**Files:**
- Create: `foxgita/Models/SchemaV9.swift`
- Modify: `foxgita/Models/Models.swift`
- Modify: `foxgita/foxgitaApp.swift`
- Modify: `foxgitaTests/MigrationTests.swift`

**Interfaces:**

```swift
@Model final class PracticeItem {
    @Attribute(.unique) var id: UUID
    var profileId: UUID
    var practiceDayKey: String
    var title: String
    var categoryRaw: String
    var durationSeconds: Int
    var bpm: Int?
    var timeSignature: String?
    var note: String
    var sourceRaw: String
    var originId: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \RecordingRef.practiceItem)
    var recordings: [RecordingRef]
}
```

- [ ] **Step 1: Write a failing V8-to-V9 migration test**

  测试旧 Task、Session、Recording 迁移后仍可读取，并能插入、重开一个 V9 PracticeItem。

- [ ] **Step 2: Run `MigrationTests` and verify RED**

  Expected: FAIL because `SchemaV9` is missing.

- [ ] **Step 3: Copy V8 schema into V9 and add PracticeItem**

  保留 V8 全部模型；为 `RecordingRef` 增加可选 `practiceItem` 关系，同时保留可选 legacy `session`。

- [ ] **Step 4: Switch aliases, migration plan, and app container to V9**

  V8 → V9 使用 lightweight stage；本任务不删除旧模型或旧字段。

- [ ] **Step 5: Run focused tests and verify GREEN**

  ```bash
  xcodebuild -project foxgita.xcodeproj -scheme foxgita \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:foxgitaTests/MigrationTests test
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add foxgita/Models/SchemaV9.swift foxgita/Models/Models.swift foxgita/foxgitaApp.swift foxgitaTests/MigrationTests.swift
  git commit -m "feat: add daily practice item schema"
  ```

---

### Task 3: 建立 PracticeItem Repository 查询边界

**Files:**
- Modify: `foxgita/Services/PracticeRepository.swift`
- Modify: `foxgita/Services/PracticeStore.swift`
- Modify: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**

```swift
protocol PracticeRepository {
    func practiceItems(profileId: UUID) throws -> [PracticeItem]
    func practiceItem(id: UUID, profileId: UUID) throws -> PracticeItem?
    func insertPracticeItem(_ item: PracticeItem) throws
    func save() throws
}
```

- [ ] **Step 1: Write failing repository contract tests**

  覆盖 profile 隔离、按 id 查询、软删除不进入默认集合、相同 id 只返回一条。

- [ ] **Step 2: Run `PracticeStoreTests` and verify RED**

- [ ] **Step 3: Add SwiftData and in-memory implementations**

  默认查询只返回 `deletedAt == nil` 的新模型；旧 Task/Session API 标为 legacy 但暂不删除。

- [ ] **Step 4: Add the model-to-snapshot adapter**

  UI 和统计只接收值类型 snapshot，不直接散布 SwiftData 查询规则。

- [ ] **Step 5: Verify GREEN and commit**

  ```bash
  git add foxgita/Services/PracticeRepository.swift foxgita/Services/PracticeStore.swift foxgitaTests/PracticeStoreTests.swift
  git commit -m "feat: add practice item repository APIs"
  ```

---

### Task 4: 实现一次创建、绝对时长覆盖保存

**Files:**
- Modify: `foxgita/Services/PracticeStore.swift`
- Modify: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**

```swift
struct PracticeItemInput {
    let title: String
    let category: PracticeCategory
    let source: PracticeItemSource
    let originId: String?
    let bpm: Int?
    let timeSignature: String?
}

func createPracticeItem(input: PracticeItemInput, now: Date, calendar: Calendar) throws -> PracticeItem
func savePracticeItem(id: UUID, durationSeconds: Int, note: String, now: Date) throws
```

- [ ] **Step 1: Write failing creation and idempotency tests**

  创建立即持久化一个 item；连续以 600 秒保存两次最终仍为 600；保存不改变日期键；负时长归零。

- [ ] **Step 2: Run focused tests and verify RED**

- [ ] **Step 3: Implement the only new-practice creation API**

  创建时生成 id 和固定日期键，不创建配套 Session、Draft 或 TaskItem。

- [ ] **Step 4: Implement absolute save and soft delete**

  `durationSeconds = max(0, suppliedValue)`；笔记和更新时间同事务保存；删除设置 `deletedAt`。

- [ ] **Step 5: Add regression coverage for repeated Save and onDisappear**

  同一详情对象多次保存、离开自动保存、重进后再保存均不累加。

- [ ] **Step 6: Verify GREEN and commit**

  ```bash
  git add foxgita/Services/PracticeStore.swift foxgitaTests/PracticeStoreTests.swift
  git commit -m "feat: save practice item time idempotently"
  ```

---

### Task 5: 将录音归属切到 PracticeItem

**Files:**
- Modify: `foxgita/Services/RecordingStore.swift`
- Modify: `foxgita/Services/PracticeStore.swift`
- Modify: `foxgitaTests/RecordingStoreTests.swift`
- Modify: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**

```swift
func attachRecording(_ recording: RecordingRef, toPracticeItemId itemId: UUID) throws

enum PracticeReviewContext {
    case practiceItem(UUID)
    case legacySession(UUID)
}
```

- [ ] **Step 1: Write failing ownership tests**

  新录音不要求 Session；删除 item 级联删除它的新录音；legacy Session 录音仍可读。

- [ ] **Step 2: Run `RecordingStoreTests` and verify RED**

- [ ] **Step 3: Implement dual-read, item-only-new-write behavior**

  新详情页只写 `practiceItem` 关系；复盘显式区分新 item 与 legacy Session，禁止创建空 Session。

- [ ] **Step 4: Run RecordingStore and PracticeStore tests**

- [ ] **Step 5: Commit**

  ```bash
  git add foxgita/Services/RecordingStore.swift foxgita/Services/PracticeStore.swift foxgitaTests/RecordingStoreTests.swift foxgitaTests/PracticeStoreTests.swift
  git commit -m "feat: attach recordings to practice items"
  ```

---

### Task 6: 用 PracticeItem 重建主页日期与日历状态

**Files:**
- Modify: `foxgita/Features/Practice/PracticeView.swift`
- Modify: `foxgita/Services/StatsAggregator.swift`
- Modify: `foxgitaTests/StatsAggregatorTests.swift`
- Create: `foxgitaTests/PracticeHomeStateTests.swift`

**Interfaces:**

```swift
struct PracticeHomeState: Equatable {
    let selectedDayKey: String
    let items: [PracticeItemSnapshot]
    let totalDurationSeconds: Int
    let checkedInDayKeys: Set<String>

    static func make(selectedDayKey: String, allItems: [PracticeItemSnapshot]) -> Self
}
```

- [ ] **Step 1: Write failing home-state tests**

  覆盖点击 25 号只显示 25 号 item、26 号内容不串入；同一 item 多次保存仍一行；总时长为该日 items 之和；日历标记与列表同源。

- [ ] **Step 2: Run the new tests and verify RED**

- [ ] **Step 3: Implement `PracticeHomeState` using Task 1 rules**

  不维护 `activeTasks`、`dayGroups`、Session 次数或“本周次数”。

- [ ] **Step 4: Replace PracticeView data source**

  查询当前 profile 的有效 items；点击日历只改变 `selectedDayKey`；今天和历史使用同一行组件，点击携带 item id。

- [ ] **Step 5: Preserve calendar and check-in behavior**

  任一有效 item 使当日打卡；零时长 item 仍表示实际练过，但总时长为 0。

- [ ] **Step 6: Remove practice-count presentation**

  删除“本周次数”“N 次本周”等文案与计算。

- [ ] **Step 7: Verify tests and commit**

  ```bash
  xcodebuild -project foxgita.xcodeproj -scheme foxgita \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:foxgitaTests/PracticeHomeStateTests \
    -only-testing:foxgitaTests/StatsAggregatorTests test

  git add foxgita/Features/Practice/PracticeView.swift foxgita/Services/StatsAggregator.swift foxgitaTests/StatsAggregatorTests.swift foxgitaTests/PracticeHomeStateTests.swift
  git commit -m "feat: drive practice home from daily items"
  ```

---

### Task 7: 将详情页改为 PracticeItem 单模型编辑

**Files:**
- Modify: `foxgita/App/AppRouter.swift`
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`
- Modify: `foxgitaTests/AppRouterTests.swift`
- Create: `foxgitaTests/PracticeDetailStateTests.swift`

**Interfaces:**

```swift
enum AppRoute: Hashable {
    case practiceDetail(itemId: UUID)
}

enum PracticeDetailMode: Equatable {
    case editable
    case historical
}
```

- [ ] **Step 1: Write failing route and detail-state tests**

  主页只用 item id 导航；今天可编辑计时，历史日期只读；详情内容与主页同一 item 一致。

- [ ] **Step 2: Run focused tests and verify RED**

- [ ] **Step 3: Change the practice-detail route payload to itemId**

  不影响记录页仍需使用的 legacy Session 路由。

- [ ] **Step 4: Replace session restoration with item loading**

  按 id 加载唯一 item；计时从 `durationSeconds` 起步；保存调用绝对覆盖 API；删除“查找最新 Session 并恢复”。

- [ ] **Step 5: Enforce historical read-only mode**

  日期键不是今天时不启动计时、不自动写回，仍可查看笔记、录音和复盘。

- [ ] **Step 6: Verify the 25th-day navigation regression**

  从 25 号列表进入后仍展示 25 号 item，不受当前日期或同标题数据影响。

- [ ] **Step 7: Run tests and commit**

  ```bash
  xcodebuild -project foxgita.xcodeproj -scheme foxgita \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:foxgitaTests/AppRouterTests \
    -only-testing:foxgitaTests/PracticeDetailStateTests test

  git add foxgita/App/AppRouter.swift foxgita/Features/Practice/PracticeDetailView.swift foxgitaTests/AppRouterTests.swift foxgitaTests/PracticeDetailStateTests.swift
  git commit -m "refactor: edit practice items directly"
  ```

---

### Task 8: 切换所有练习创建入口

**Files:**
- Modify: `foxgita/Features/Practice/RecommendSheet.swift`
- Modify: `foxgita/Features/Practice/PhotoPracticeSheet.swift`
- Modify: `foxgita/Features/Practice/NextSessionSheet.swift`
- Modify: `foxgita/Features/Practice/PracticeView.swift`
- Modify: `foxgitaTests/PracticeStoreTests.swift`

- [ ] **Step 1: Add failing entry-point regression tests**

  每个入口创建后新增恰好一个 PracticeItem、零个 Session、零个新 TaskItem，并导航到该 item；同一次 action token 重复回调也只创建一次。

- [ ] **Step 2: Run focused tests and verify RED**

- [ ] **Step 3: Route manual, recommendation, photo, and next actions through `createPracticeItem`**

  推荐或模板内容只复制为当天实际 item 的初始字段，不保存跨天归属。

- [ ] **Step 4: Guard one UI action against duplicate creation**

  提交期间禁用按钮并持有 action token；它只防双击/重复回调，不按标题合并用户真实发起的两次练习。

- [ ] **Step 5: Test cancellation and generation failures**

  取消 sheet 不创建 item，生成失败不留下半成品。

- [ ] **Step 6: Verify GREEN and commit**

  ```bash
  git add foxgita/Features/Practice/RecommendSheet.swift foxgita/Features/Practice/PhotoPracticeSheet.swift foxgita/Features/Practice/NextSessionSheet.swift foxgita/Features/Practice/PracticeView.swift foxgitaTests/PracticeStoreTests.swift
  git commit -m "refactor: create daily items from practice entry points"
  ```

---

### Task 9: 清理新链路中的 Session/Draft 依赖并验收

**Files:**
- Modify: `foxgita/Features/Practice/PracticeView.swift`
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`
- Modify: `foxgita/Services/PracticeStore.swift`
- Modify: `docs/superpowers/specs/2026-08-26-Gita-练习主页日级练习项-开发文档.md`

- [ ] **Step 1: Search for forbidden new-flow dependencies**

  ```bash
  rg -n 'PracticeSession|openSession|finishSession|Draft|本周次数|次本周' \
    foxgita/Features/Practice/PracticeView.swift \
    foxgita/Features/Practice/PracticeDetailView.swift
  ```

  Expected: no matches. Legacy record/history code elsewhere may remain.

- [ ] **Step 2: Run the complete suite**

  ```bash
  xcodebuild -project foxgita.xcodeproj -scheme foxgita \
    -destination 'platform=iOS Simulator,name=iPhone 17' test
  ```

  Expected: zero failures.

- [ ] **Step 3: Perform simulator acceptance checks**

  1. 当天创建“知足跟着原唱缝2”，计时到 10 分钟并保存两次。
  2. 返回主页，该练习只出现一次且显示 10 分钟。
  3. 再进入详情，仍显示同一 item 和 10 分钟。
  4. 点击前一天，不出现今天的练习；返回今天后重新出现。
  5. 今天显示日历打卡，未练习日期不显示。
  6. 主页没有练习次数；当日总时长只来自当日 items。
  7. 跨午夜后打开旧 item，不移动日期，也不允许继续计时写回。

- [ ] **Step 4: Record the legacy-data release gate in the spec**

  V9 首期只保证旧数据可读，不把 Session 推断成新 item；正式发布前另行决定隐藏旧数据或提供显式迁移工具，禁止静默合并导致重复。

- [ ] **Step 5: Inspect the final diff**

  ```bash
  git status --short
  git diff --check
  git diff --stat
  ```

  确认未覆盖本地化改动、未删除 legacy 记录能力、未引入 Project 概念。

- [ ] **Step 6: Commit final cleanup**

  ```bash
  git add foxgita/Features/Practice/PracticeView.swift foxgita/Features/Practice/PracticeDetailView.swift foxgita/Services/PracticeStore.swift docs/superpowers/specs/2026-08-26-Gita-练习主页日级练习项-开发文档.md
  git commit -m "chore: finalize daily practice item rollout"
  ```

## Done Definition

- 练习主页、日历、日期列表、详情和时长统计读取同一个 PracticeItem 数据源。
- 保存两次不会增加行数或累计两次时长。
- 点击任意历史日期只展示该日期固定归属的练习项。
- 新流程不创建 Session、Draft 或跨天 TaskItem。
- 产品不展示练习次数。
- 旧 Session 数据没有被错误复制或静默合并。
- 全量测试通过，用户截图所述路径的人工验收通过。

