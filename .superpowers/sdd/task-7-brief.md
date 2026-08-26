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

