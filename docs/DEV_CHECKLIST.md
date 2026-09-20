# foxgita 日常开发 Checklist

> 目标：把单次 fix / 小功能从「等 Agent 1–2 小时」压到 **30–45 分钟**。  
> 配套测试命令见 [TEST_PLAN_CLI.md](./TEST_PLAN_CLI.md)。

工作目录：`/Users/haizei/work/AI/program/gita/foxgita`

---

## 0. 开工前（2 分钟）

- [ ] **一个新 bug / 一个小功能 = 一个新 Cursor 对话**（别在长上下文里续聊）
- [ ] 复制下方「Agent 起手模板」，填好再发
- [ ] 模型：**Composer 2.5**（日常）/ **Sonnet 级**（迁移、难 bug）/ 只有架构级才用 Opus

### Agent 起手模板

```text
【现象】（真机/模拟器、能否复现、截图或 crash 时间）
【期望】（成功标准，一句话）
【范围】只改这些文件：（列出 1–3 个路径；没有就先 Ask 定位）
【不要】refactor、动 Schema 除非我明确说、别改无关测试
【验证】跑这些命令 / UI test：（见下文 §4）
```

---

## 1. 分阶段委托（别一次丢给 Agent 全权排查）

| 阶段 | 你做什么 | Cursor 模式 | 目标时间 |
|------|----------|-------------|----------|
| 定范围 | 填起手模板 | Ask | 5 min |
| 定位 | 「只读 X/Y，给根因，不改代码」 | Agent | 10–15 min |
| 实现 | 「按方案只改列出的文件」 | Agent | 15–20 min |
| 验证 | **你自己**跑模拟器 + 定向 test | Xcode / 终端 | 10 min |
| 真机 | 仅手势 / 真机独有 / 发布前 | Xcode Cmd+R | 10 min |
| 提交 | 你确认后再 `git commit` | — | 5 min |

---

## 2. SwiftData 迁移（踩过坑，必看）

**已发布到真机的 `GitaSchemaVN` 禁止原地改字段。**

正确做法：

1. 复制当前 schema → 新建 `SchemaV(N+1).swift`
2. `Models.swift`：typealias 指向新版本 + `GitaMigrationPlan` 加 `.lightweight(VN → V(N+1))`
3. `foxgitaApp.swift`：`Schema(versionedSchema: GitaSchemaV(N+1).self)`
4. `MigrationTests` 加：**旧库写入 → 新 plan 打开不崩、数据还在**

错误症状：`Cannot use staged migration with an unknown model version` → 启动即闪退。

当前版本：**V16**（V15 = + metronomeAccentRaw；V16 = + metronomeSubdivisionRaw）。

---

## 3. 高风险区域（改完必跑冒烟）

这些文件/regression 和「整 app 卡住 / 加号消失 / Tab 点不了」强相关：

| 区域 | 文件 | 手动看一眼 |
|------|------|------------|
| 周条分页 | `Components/SharedUI.swift`（`StreakCard`） | 首页显示**当前周**，今天高亮；右下角 **＋** 在 |
| Tab 点击 | `Components/SharedUI.swift`（`PageBackground`） | 记录 / 设置 Tab 能点 |
| 主 Tab | `App/MainTabView.swift` | 三个 Tab 可切换 |
| 启动 / DB | `foxgitaApp.swift`、`Models/` | 冷启动不闪退 |
| 练习首页 | `Features/Practice/PracticeView.swift` | 「今日练习」+ 列表 / 空态 |

---

## 4. 快速验证命令（优先模拟器，别一上来全量 + 真机）

模拟器名按本机调整（`iPhone 17` 或 `iPhone 17,OS=26.5`）。

### 4.1 最小冒烟（~2–3 分钟）— 改 UI / 导航 / 周条后必跑

```bash
cd /Users/haizei/work/AI/program/gita/foxgita

xcodebuild test -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaUITests/PracticeFlowUITests/testLaunchShowsTodayPractice \
  -only-testing:foxgitaUITests/PracticeFlowUITests/testCreateCustomTaskOpensDetail \
  -only-testing:foxgitaUITests/PracticeFlowUITests/testRecordTabOpensFromTabBar
```

**通过标准：**

- 见「今日练习」、周条 `week-pager` 存在
- 「添加练习」→ 推荐 Sheet → 能创建并进详情
- 记录 Tab 能打开

### 4.2 改了 Models / 迁移 — 加跑

```bash
xcodebuild test -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MigrationTests
```

### 4.3 改了 Store / 统计 — 加跑

```bash
xcodebuild test -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests \
  -only-testing:foxgitaTests/StatsAggregatorTests
```

### 4.4 发布前 / 大改 — 全量

见 [TEST_PLAN_CLI.md](./TEST_PLAN_CLI.md) Step B / C。

### 4.5 真机闪退排查（仅当模拟器通过仍复现）

```bash
# 控制台启动，看 SwiftData / fatalError
xcrun devicectl device process launch --console --terminate-existing \
  --device <DEVICE_ID> com.haizei.foxgita

# 拉 crash log
xcrun devicectl device copy from --device <DEVICE_ID> \
  --domain-type systemCrashLogs --source . --destination /tmp/foxgita-crash
```

---

## 5. 模拟器 vs 真机

| 场景 | 用 |
|------|-----|
| 逻辑、UI 文案、导航、加号、Tab | **模拟器** |
| 麦克风 / 相机 / 来电打断 | 真机 |
| 手势手感、TabBar 遮挡、启动闪退（曾只在真机出现） | 模拟器绿后再 **真机点一遍** |

日常：**80% 模拟器 + 定向 test，20% 真机确认**。

---

## 6. Cursor 用量控制

- 日常 Agent：**Composer 2.5**（走 Cursor Models 池，便宜）
- 同一任务别反复「全盘再查一遍」— 用 §1 分阶段
- 大日志 / crash 先自己贴 **关键 20 行**，别让 Agent 盲搜
- 额度： [cursor.com/dashboard/spending](https://cursor.com/dashboard/spending)

---

## 7. 提交前（5 分钟）

- [ ] §4 对应 test 全绿
- [ ] 模拟器肉眼走一遍：练习 → 加号 → 记录 Tab → 设置
- [ ] 若动 Schema：MigrationTests 绿 + 真机冷启动一次
- [ ] `git status` 只有本任务相关文件
- [ ] commit message 写 **为什么**（中文或英文均可，与仓库风格一致）
- [ ] 需要时再 `git push`（不默认 push）

---

## 8. 本仓库快捷路径

```
foxgita/
├── foxgitaApp.swift          # 启动、ModelContainer
├── App/MainTabView.swift     # 三 Tab
├── Components/SharedUI.swift # 周条、PageBackground、卡片
├── Features/Practice/        # 练习首页、详情
├── Features/Record/          # 记录、项目
├── Models/SchemaV*.swift     # 只增不改旧版
├── foxgitaTests/MigrationTests.swift
└── foxgitaUITests/PracticeFlowUITests.swift
```

---

## 9. 时间预算参考

| 类型 | 目标总时长 |
|------|------------|
| 文案 / 小 UI | 20–30 min |
| 单文件 bug | 30–45 min |
| 跨 2–3 文件功能 | 45–90 min |
| Schema 迁移 | 60–120 min（含 MigrationTests + 真机） |

超过预算 → 停 Agent，拆 ticket 或换 Ask 先收窄范围。
