# 首页每日练习清空与节奏卡移除 Implementation Plan

> **功能需求：** [`../specs/2026-08-19-today-practice-empty-design.md`](../specs/2026-08-19-today-practice-empty-design.md)。本文为逐步施工单。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make「今日练习」show only tasks whose `startedOn` falls on the device’s current local day, allow the same recommend template to be added again on a later day, and remove the home-screen week-rhythm card without touching history data.

**Architecture:** Pure `PracticeTaskRules` decide visibility, local day keys, and midnight selected-day snap. `PracticeStore.activateTemplate` mints `active-{templateId}-{yyyy-MM-dd}` and reuses or restores today’s instance. `PracticeView` filters the inbox, updates empty copy, drops the rhythm card, and calls the snap helper on appear / scene active. No Schema change, no Clock protocol, no midnight deletes.

**Tech Stack:** SwiftUI · SwiftData · Swift Testing · XCTest UI · existing PracticeStore / AppRouter / PracticeRecordRules

## Global Constraints

- Spec: `docs/superpowers/2026-08-19-today-practice-empty/specs/2026-08-19-today-practice-empty-design.md`
- iOS 18+ · Scheme `foxgita` · synchronized Xcode groups (new files under `foxgita/` / `foxgitaTests/` auto-join targets)
- No SwiftData schema change; reuse `TaskItem` / `PracticeSession`
- Do not delete or rewrite yesterday’s tasks at midnight or launch; filter on read
- Do not inject a Clock protocol; pass `now` / `calendar` into pure functions and `activateTemplate`
- Do not add `now` to `createCustomTask` / `createFromAIDraft`
- Do not change Record Tab, History, or `StatsAggregator` session aggregation
- Do not implement 主行动卡, 零配置默认模板, or yesterday carry-over
- Empty copy (verbatim): title `今天还没加练习`; subtitle `点右下角加号，挑一项开始`
- Copy language: `zh-Hans` via `String(localized:)` / String Catalog
- Unit test command (cwd `foxgita/`): `xcodebuild -project foxgita.xcodeproj -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:foxgitaTests test` (swap simulator name if needed)
- YAGNI: no P1 localization-key cleanup, no P2 Clock, no「最近录入」入口

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/PracticeTaskRules.swift` | `localDayKey`, `isVisibleToday`, `snapSelectedDayIfItWasToday` |
| `foxgitaTests/PracticeTaskRulesTests.swift` | Date-boundary unit tests |
| `foxgitaTests/PracticeRecordRulesTests.swift` | `active-` prefix still matches daily IDs |
| `foxgita/Services/PracticeRepository.swift` | `taskIncludingDeleted(id:)` on protocol + SwiftData + InMemory |
| `foxgita/Services/PracticeStore.swift` | Daily template ID, legacy reuse, same-day restore / reactivate |
| `foxgitaTests/PracticeStoreTests.swift` | Template same-day / cross-day / legacy / restore |
| `foxgita/Features/Practice/PracticeView.swift` | Filter, empty copy, remove rhythm card, wire snap |
| `foxgitaUITests/PracticeFlowUITests.swift` | Empty copy + rhythm card absence |
| `docs/TECHNICAL.md` | Today-list rule, `activateTemplate` ID, drop 按日任务规划 next-step |
| `docs/superpowers/2026-08-15-practice-tab/specs/2026-08-15-practice-tab-design.md` | Supersession note |

---

### Task 1: PracticeTaskRules

**Files:**
- Create: `foxgita/Services/PracticeTaskRules.swift`
- Test: `foxgitaTests/PracticeTaskRulesTests.swift`
- Modify: `foxgitaTests/PracticeRecordRulesTests.swift`

**Interfaces:**
- Consumes: `PracticeRecordRules.isUserAddedTask(id:)`, `TaskItem` fields (`startedOn`, `status`, `isTemplate`, `deletedAt`, `id`)
- Produces:
  - `enum PracticeTaskRules`
  - `static func localDayKey(for date: Date, calendar: Calendar) -> String`
  - `static func isVisibleToday(task: TaskItem, on date: Date, calendar: Calendar) -> Bool`
  - `static func snapSelectedDayIfItWasToday(selectedDay: Date, lastSeenTodayStart: Date?, now: Date, calendar: Calendar) -> (selectedDay: Date, lastSeenTodayStart: Date)`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/PracticeTaskRulesTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

struct PracticeTaskRulesTests {
    private func shanghai() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
    }

    private func makeTask(
        id: String = "custom-1",
        startedOn: Date?,
        status: TaskStatus = .active,
        isTemplate: Bool = false,
        deletedAt: Date? = nil
    ) -> TaskItem {
        let task = TaskItem(
            id: id, title: "t", subtitle: "s",
            category: .chord, targetMin: 5,
            status: status, startedOn: startedOn,
            isTemplate: isTemplate
        )
        task.deletedAt = deletedAt
        return task
    }

    @Test func localDayKeyUsesCalendarComponentsNotUTC() {
        let cal = shanghai()
        let late = date(2026, 8, 19, 23, calendar: cal)
        let early = date(2026, 8, 20, 0, calendar: cal)
        #expect(PracticeTaskRules.localDayKey(for: late, calendar: cal) == "2026-08-19")
        #expect(PracticeTaskRules.localDayKey(for: early, calendar: cal) == "2026-08-20")
    }

    @Test func localDayKeyCrossesMonthAndYear() {
        let cal = shanghai()
        #expect(
            PracticeTaskRules.localDayKey(
                for: date(2026, 8, 31, 23, calendar: cal), calendar: cal
            ) == "2026-08-31"
        )
        #expect(
            PracticeTaskRules.localDayKey(
                for: date(2026, 9, 1, 0, calendar: cal), calendar: cal
            ) == "2026-09-01"
        )
        #expect(
            PracticeTaskRules.localDayKey(
                for: date(2026, 12, 31, 23, calendar: cal), calendar: cal
            ) == "2026-12-31"
        )
        #expect(
            PracticeTaskRules.localDayKey(
                for: date(2027, 1, 1, 0, calendar: cal), calendar: cal
            ) == "2027-01-01"
        )
    }

    @Test func visibleTodayRequiresSameLocalDay() {
        let cal = shanghai()
        let today = date(2026, 8, 19, 10, calendar: cal)
        let yesterday = date(2026, 8, 18, 10, calendar: cal)
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: today), on: today, calendar: cal
            )
        )
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: yesterday), on: today, calendar: cal
            ) == false
        )
    }

    @Test func visibleTodayRejectsNilTemplateDeletedDoneAndSeed() {
        let cal = shanghai()
        let today = date(2026, 8, 19, 10, calendar: cal)
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: nil), on: today, calendar: cal
            ) == false
        )
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: today, isTemplate: true),
                on: today, calendar: cal
            ) == false
        )
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: today, deletedAt: today),
                on: today, calendar: cal
            ) == false
        )
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: today, status: .done),
                on: today, calendar: cal
            ) == false
        )
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(id: "warm", startedOn: today),
                on: today, calendar: cal
            ) == false
        )
    }

    @Test func snapMovesSelectedDayOnlyWhenItWasToday() {
        let cal = shanghai()
        let aug18 = cal.startOfDay(for: date(2026, 8, 18, calendar: cal))
        let aug17 = cal.startOfDay(for: date(2026, 8, 17, calendar: cal))
        let aug19 = date(2026, 8, 19, 0, calendar: cal)

        let rolled = PracticeTaskRules.snapSelectedDayIfItWasToday(
            selectedDay: aug18, lastSeenTodayStart: aug18, now: aug19, calendar: cal
        )
        #expect(cal.isDate(rolled.selectedDay, inSameDayAs: aug19))
        #expect(cal.isDate(rolled.lastSeenTodayStart, inSameDayAs: aug19))

        let browsing = PracticeTaskRules.snapSelectedDayIfItWasToday(
            selectedDay: aug17, lastSeenTodayStart: aug18, now: aug19, calendar: cal
        )
        #expect(cal.isDate(browsing.selectedDay, inSameDayAs: aug17))
        #expect(cal.isDate(browsing.lastSeenTodayStart, inSameDayAs: aug19))
    }
}
```

Add this assertion to `userAddedAcceptsCustomAndActivePrefixes` in `foxgitaTests/PracticeRecordRulesTests.swift`:

```swift
#expect(PracticeRecordRules.isUserAddedTask(id: "active-tpl-chord-2026-08-19"))
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeTaskRulesTests \
  test
```

Expected: compile error — `PracticeTaskRules` not found.

- [ ] **Step 3: Minimal implementation**

Create `foxgita/Services/PracticeTaskRules.swift`:

```swift
import Foundation

enum PracticeTaskRules {
    static func localDayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }

    static func isVisibleToday(task: TaskItem, on date: Date, calendar: Calendar) -> Bool {
        guard let startedOn = task.startedOn else { return false }
        guard calendar.isDate(startedOn, inSameDayAs: date) else { return false }
        guard task.status == .active else { return false }
        guard task.isTemplate == false else { return false }
        guard task.deletedAt == nil else { return false }
        return PracticeRecordRules.isUserAddedTask(id: task.id)
    }

    static func snapSelectedDayIfItWasToday(
        selectedDay: Date,
        lastSeenTodayStart: Date?,
        now: Date,
        calendar: Calendar
    ) -> (selectedDay: Date, lastSeenTodayStart: Date) {
        let today = calendar.startOfDay(for: now)
        if calendar.isDate(selectedDay, inSameDayAs: today) {
            return (selectedDay: today, lastSeenTodayStart: today)
        }
        if let last = lastSeenTodayStart, calendar.isDate(selectedDay, inSameDayAs: last) {
            return (selectedDay: today, lastSeenTodayStart: today)
        }
        return (selectedDay: selectedDay, lastSeenTodayStart: today)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeTaskRulesTests \
  -only-testing:foxgitaTests/PracticeRecordRulesTests \
  test
```

Expected: PASS (both test classes).

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeTaskRules.swift \
  foxgitaTests/PracticeTaskRulesTests.swift \
  foxgitaTests/PracticeRecordRulesTests.swift
git commit -m "feat: filter today visibility by local startedOn"
```

---

### Task 2: Daily template instances

**Files:**
- Modify: `foxgita/Services/PracticeRepository.swift` (protocol around line 15; SwiftData `task(id:)` around 78–82; InMemory `task(id:)` around 143–145)
- Modify: `foxgita/Services/PracticeStore.swift` (`activateTemplate` 66–88)
- Test: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**
- Consumes: `PracticeTaskRules.localDayKey(for:calendar:)`, `PracticeRepository.task(id:)`, new `taskIncludingDeleted(id:)`
- Produces:
  - `func taskIncludingDeleted(id: String) throws -> TaskItem?`
  - `func activateTemplate(_ templateId: String, now: Date = Date(), calendar: Calendar = .current) -> String?`
  - Daily ID format `active-{templateId}-{yyyy-MM-dd}`
  - Same-day restore of soft-deleted daily instance; same-day `.done` → `.active`; legacy `active-{templateId}` reused only when `startedOn` is today

- [ ] **Step 1: Write the failing tests**

In `foxgitaTests/PracticeStoreTests.swift`, add the same `shanghai()` / `date(_:)` helpers used in Task 1 (private methods on `PracticeStoreTests`). Replace the two existing template tests and add the new ones:

```swift
private func shanghai() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return cal
}

private func date(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10,
    calendar: Calendar? = nil
) -> Date {
    let cal = calendar ?? shanghai()
    return cal.date(from: DateComponents(
        year: year, month: month, day: day, hour: hour
    ))!
}

@Test func activateTemplateCreatesActiveCopy() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedTemplate(into: repo)
    let cal = shanghai()
    let now = date(2026, 8, 19, calendar: cal)

    let id = store.activateTemplate("tpl-chord", now: now, calendar: cal)
    #expect(id == "active-tpl-chord-2026-08-19")
    let active = try #require(try repo.task(id: "active-tpl-chord-2026-08-19"))
    #expect(active.isTemplate == false)
    #expect(active.title == "和弦模板")
    #expect(active.status == .active)
    #expect(cal.isDate(active.startedOn ?? .distantPast, inSameDayAs: now))
}

@Test func activateTemplateIsIdempotent() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedTemplate(into: repo)
    let cal = shanghai()
    let now = date(2026, 8, 19, calendar: cal)
    #expect(store.activateTemplate("tpl-chord", now: now, calendar: cal) == "active-tpl-chord-2026-08-19")
    #expect(store.activateTemplate("tpl-chord", now: now, calendar: cal) == "active-tpl-chord-2026-08-19")
    #expect(try repo.tasks().filter { $0.id.hasPrefix("active-") }.count == 1)
}

@Test func activateTemplateCreatesNewInstanceNextDay() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedTemplate(into: repo)
    let cal = shanghai()
    let day1 = date(2026, 8, 19, calendar: cal)
    let day2 = date(2026, 8, 20, calendar: cal)
    #expect(store.activateTemplate("tpl-chord", now: day1, calendar: cal) == "active-tpl-chord-2026-08-19")
    #expect(store.activateTemplate("tpl-chord", now: day2, calendar: cal) == "active-tpl-chord-2026-08-20")
    let old = try #require(try repo.task(id: "active-tpl-chord-2026-08-19"))
    #expect(cal.isDate(old.startedOn ?? .distantPast, inSameDayAs: day1))
    #expect(try repo.tasks().filter { $0.id.hasPrefix("active-") }.count == 2)
}

@Test func activateTemplateReusesLegacyIdWhenStartedToday() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedTemplate(into: repo)
    let cal = shanghai()
    let now = date(2026, 8, 19, calendar: cal)
    let legacy = TaskItem(
        id: "active-tpl-chord", title: "和弦模板", subtitle: "8 分钟",
        category: .chord, targetMin: 8, startedOn: now, sortOrder: 10
    )
    try repo.add(legacy)
    try repo.save()
    #expect(store.activateTemplate("tpl-chord", now: now, calendar: cal) == "active-tpl-chord")
    #expect(try repo.task(id: "active-tpl-chord-2026-08-19") == nil)
}

@Test func activateTemplateSkipsLegacyIdFromYesterday() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedTemplate(into: repo)
    let cal = shanghai()
    let yesterday = date(2026, 8, 18, calendar: cal)
    let today = date(2026, 8, 19, calendar: cal)
    let legacy = TaskItem(
        id: "active-tpl-chord", title: "和弦模板", subtitle: "8 分钟",
        category: .chord, targetMin: 8, startedOn: yesterday, sortOrder: 10
    )
    try repo.add(legacy)
    try repo.save()
    #expect(store.activateTemplate("tpl-chord", now: today, calendar: cal) == "active-tpl-chord-2026-08-19")
    #expect(try repo.task(id: "active-tpl-chord") != nil)
}

@Test func activateTemplateRestoresSameDayDeletedInstance() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedTemplate(into: repo)
    let cal = shanghai()
    let now = date(2026, 8, 19, calendar: cal)
    let id = try #require(store.activateTemplate("tpl-chord", now: now, calendar: cal))
    store.softDeleteTask(id)
    #expect(try repo.task(id: id) == nil)
    #expect(store.activateTemplate("tpl-chord", now: now, calendar: cal) == id)
    let restored = try #require(try repo.task(id: id))
    #expect(restored.deletedAt == nil)
    #expect(restored.status == .active)
    #expect(try repo.tasks().filter { $0.id.hasPrefix("active-") }.count == 1)
}

@Test func activateTemplateReactivatesDoneInstanceSameDay() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedTemplate(into: repo)
    let cal = shanghai()
    let now = date(2026, 8, 19, calendar: cal)
    let id = try #require(store.activateTemplate("tpl-chord", now: now, calendar: cal))
    store.setTaskStatus(id, to: .done)
    #expect(store.activateTemplate("tpl-chord", now: now, calendar: cal) == id)
    #expect(try repo.task(id: id)?.status == .active)
}
```

Keep `activateMissingTemplateSetsNotFound` unchanged.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests \
  test
```

Expected: FAIL — extra argument `now:` / still returns `active-tpl-chord`, or `taskIncludingDeleted` missing.

- [ ] **Step 3: Minimal implementation**

In `PracticeRepository` protocol, add next to `task(id:)`:

```swift
func taskIncludingDeleted(id: String) throws -> TaskItem?
```

SwiftData:

```swift
func taskIncludingDeleted(id: String) throws -> TaskItem? {
    try context.fetch(
        FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
    ).first
}
```

InMemory (search `storedTasks` so tombstones remain visible):

```swift
func taskIncludingDeleted(id: String) throws -> TaskItem? {
    storedTasks.first { $0.id == id }
}
```

Replace `activateTemplate` in `PracticeStore.swift`:

```swift
@discardableResult
func activateTemplate(
    _ templateId: String,
    now: Date = Date(),
    calendar: Calendar = .current
) -> String? {
    guard let template = try? repository.task(id: templateId) else {
        lastError = .notFound
        return nil
    }
    guard template.isTemplate else { return template.id }

    let dayKey = PracticeTaskRules.localDayKey(for: now, calendar: calendar)
    let dailyId = "active-\(template.id)-\(dayKey)"
    let legacyId = "active-\(template.id)"

    if let existing = try? repository.task(id: dailyId) {
        return ensureActive(existing)
    }
    if let tombstone = try? repository.taskIncludingDeleted(id: dailyId),
       tombstone.deletedAt != nil {
        return ensureActive(tombstone)
    }
    if let legacy = try? repository.task(id: legacyId),
       let started = legacy.startedOn,
       calendar.isDate(started, inSameDayAs: now) {
        return ensureActive(legacy)
    }

    let copy = TaskItem(
        id: dailyId, title: template.title, subtitle: template.subtitle,
        category: template.category, targetMin: template.targetMin,
        defaultBpm: template.defaultBpm, timeSig: template.timeSig,
        steps: template.steps, status: .active, startedOn: now,
        sortOrder: template.sortOrder, isTemplate: false
    )
    return produce {
        try repository.add(copy)
        try repository.save()
        return copy.id
    }
}

private func ensureActive(_ task: TaskItem) -> String? {
    if task.status == .active && task.deletedAt == nil { return task.id }
    return produce {
        task.deletedAt = nil
        task.status = .active
        task.touch()
        try repository.save()
        return task.id
    }
}
```

Place `ensureActive` with the other private helpers (`perform` / `produce`). Do not change `createCustomTask` or `createFromAIDraft`.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests \
  -only-testing:foxgitaTests/PracticeTaskRulesTests \
  test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeRepository.swift \
  foxgita/Services/PracticeStore.swift \
  foxgitaTests/PracticeStoreTests.swift
git commit -m "feat: mint daily template instances with legacy id reuse"
```

---

### Task 3: PracticeView + UI smoke

**Files:**
- Modify: `foxgita/Features/Practice/PracticeView.swift` (`activeTasks` 56–58, `weekMinutes` 73–75, rhythm card 137–163, empty copy 308–312, reminder/return `onChange` 277–291, `body` modifiers)
- Test: `foxgitaUITests/PracticeFlowUITests.swift` (`testLaunchShowsTodayPractice`)

**Interfaces:**
- Consumes: `PracticeTaskRules.isVisibleToday(task:on:calendar:)`, `PracticeTaskRules.snapSelectedDayIfItWasToday(selectedDay:lastSeenTodayStart:now:calendar:)`
- Produces: today list filtered by local day; empty copy `今天还没加练习`; no rhythm card; selected day snaps only when it was “today”

- [ ] **Step 1: Write the failing UI assertions**

In `testLaunchShowsTodayPractice` add:

```swift
XCTAssertTrue(app.staticTexts["今天还没加练习"].waitForExistence(timeout: 5))
XCTAssertFalse(app.staticTexts["还没有练习"].exists)
XCTAssertFalse(app.staticTexts["本周节奏"].exists)
XCTAssertFalse(app.staticTexts["当周节奏"].exists)
```

Keep the existing「今日练习」、`week-pager`、连续练习 assertions.

- [ ] **Step 2: Run UI test to verify it fails**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaUITests/PracticeFlowUITests/testLaunchShowsTodayPractice \
  test
```

Expected: FAIL — `今天还没加练习` missing; `本周节奏` still present on a current-week launch.

- [ ] **Step 3: Minimal view changes**

Add environment / state next to the other `@State` properties:

```swift
@Environment(\.scenePhase) private var scenePhase
@State private var lastSeenTodayStart: Date?
```

Replace `activeTasks` and delete `weekMinutes`:

```swift
private var activeTasks: [TaskItem] {
    let now = Date()
    return tasks.filter {
        PracticeTaskRules.isVisibleToday(task: $0, on: now, calendar: calendar)
    }
}
```

Add:

```swift
private func applyTodaySnap() {
    let result = PracticeTaskRules.snapSelectedDayIfItWasToday(
        selectedDay: selectedDay,
        lastSeenTodayStart: lastSeenTodayStart,
        now: Date(),
        calendar: calendar
    )
    selectedDay = result.selectedDay
    lastSeenTodayStart = result.lastSeenTodayStart
}
```

Delete the entire bottom rhythm `HStack` (the block whose title is `本周节奏` / `当周节奏`, including the「查看记录」button). Leave `StreakCard` and `taskList` in place. `weekDone` and `isVisibleWeekCurrent` stay because `StreakCard` uses them.

Change today’s empty copy:

```swift
lockedEmpty(
    title: String(localized: "今天还没加练习"),
    subtitle: String(localized: "点右下角加号，挑一项开始")
)
```

On the root `NavigationStack` content, add:

```swift
.onAppear { applyTodaySnap() }
.onChange(of: scenePhase) { _, phase in
    if phase == .active { applyTodaySnap() }
}
```

In `openTodayFirstPractice` and `returnPracticeToToday` handlers, after setting `selectedDay` to today, set `lastSeenTodayStart = calendar.startOfDay(for: Date())`. Leave the empty-guard `guard let first = activeTasks.first else { return }` as-is so a reminder with no today tasks stays on the empty state.

- [ ] **Step 4: Run UI smoke to verify it passes**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaUITests/PracticeFlowUITests \
  test
```

Expected: PASS, including create-custom, empty-complete, and recommend sheet cases.

Also run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests \
  test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Features/Practice/PracticeView.swift \
  foxgitaUITests/PracticeFlowUITests.swift \
  foxgita/Localizable.xcstrings
git commit -m "feat: show a fresh today list and drop the week rhythm card"
```

Include `Localizable.xcstrings` only if Xcode extracted the new / removed strings during the build.

---

### Task 4: Spec and TECHNICAL.md

**Files:**
- Modify: `docs/TECHNICAL.md` (§4.1.1 around 123–129, `activateTemplate` row 359, known-limits row 537, UITests blurb 495)
- Modify: `docs/superpowers/2026-08-15-practice-tab/specs/2026-08-15-practice-tab-design.md` (header)

**Interfaces:**
- Consumes: behavior from Tasks 1–3
- Produces: docs that match the shipped rules

- [ ] **Step 1: Update TECHNICAL.md**

Replace the **今天** row in §4.1.1 with:

| **今天** | `isVisibleToday`：`startedOn` 与设备当前自然日相同，且 `status == .active`、用户加入的 `custom-*` / `active-*`、非模板、未删除 | 显示 | 有 | 「开始」→ 详情 |

Add under that table:

今日列表按读时过滤，不在午夜或启动时删除昨日任务。空态文案：「今天还没加练习」。首页无「本周节奏 / 当周节奏」卡；连续练习卡与记录 Tab 仍在。跨午夜仅当选中日本来是「当时的今天」时拨到新的今天。

Replace the `activateTemplate` row:

| `activateTemplate(id, now, calendar)` | 模板 → `active-{id}-{yyyy-MM-dd}`（本地日键）当日幂等；旧 `active-{id}` 仅当 `startedOn` 是今天时复用；同日软删后恢复 |

Replace the 按日任务规划 row:

| 按日任务规划 | 「今日练习」按 `startedOn` 当地自然日过滤；模板每日新实例 | 昨日未练不结转；「最近录入」入口如需要再开 |

In the `PracticeFlowUITests` row, mention 空态「今天还没加练习」且不见节奏卡。

- [ ] **Step 2: Add supersession note**

Insert after the title block of `docs/superpowers/2026-08-15-practice-tab/specs/2026-08-15-practice-tab-design.md`:

```markdown
> **取代：** 「跨天保留今日清单」与底部「本周节奏 → 查看记录」已由 [首页每日练习清空与节奏卡移除](../../2026-08-19-today-practice-empty/specs/2026-08-19-today-practice-empty-design.md) 取代。过去日聚合与「查看」进练习详情的规则仍以本文为准。
```

- [ ] **Step 3: Commit**

```bash
git add docs/TECHNICAL.md \
  docs/superpowers/2026-08-15-practice-tab/specs/2026-08-15-practice-tab-design.md
git commit -m "docs: record daily today-list filter and rhythm card removal"
```

No test run required beyond confirming the markdown paths exist.

---

## Spec coverage (self-review)

| Spec section | Task |
|---|---|
| 4 今日可见 / `localDayKey` / `isVisibleToday` | Task 1 |
| 4.3 跨午夜 snap 算法 | Task 1 function + Task 3 wiring |
| 5 每日模板 ID、旧 ID、恢复、done→active | Task 2 |
| 5 手建/拍照不加 `now` | Task 2 (do not touch) |
| 6 空态文案、删节奏卡、提醒空态 | Task 3 |
| 7 不删历史、不改 Schema | Global + Tasks 2–3 |
| 8 单测 | Tasks 1–2 |
| 8 UI 冒烟 | Task 3 |
| 9 TECHNICAL + practice-tab 取代说明 | Task 4 |
| P1 本地化清理 / P2 Clock | Out of scope (Global Constraints) |
