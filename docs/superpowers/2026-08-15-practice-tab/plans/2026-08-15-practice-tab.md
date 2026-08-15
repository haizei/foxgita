# 练习 Tab 待练清单 + 按日回顾 Implementation Plan

> **功能需求：** [`../specs/2026-08-15-practice-tab-design.md`](../specs/2026-08-15-practice-tab-design.md)。本文为逐步施工单。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Practice tab show a user-created inbox today, one aggregated card per task on past days, and open Practice detail (not Record) from 查看.

**Architecture:** Shared predicates live in `PracticeRecordRules`. `PracticeStore.finishSession` refuses empty sessions; seed/reset write templates only. `StatsAggregator` ignores ineffective sessions for streak/week dots and adds `dayTaskGroups`. PracticeView filters today's inbox and opens detail from a past-day group; PracticeDetailView stays on the Practice tab after complete.

**Tech Stack:** SwiftUI · SwiftData · Swift Testing · XCTest UI · existing PracticeStore / AppRouter

## Global Constraints

- Spec: `docs/superpowers/2026-08-15-practice-tab/specs/2026-08-15-practice-tab-design.md`
- iOS 18+ · Scheme `foxgita` · synchronized Xcode groups (new files under `foxgita/` / `foxgitaTests/` auto-join targets)
- No SwiftData schema change; reuse `TaskItem` / `PracticeSession`
- Do not soft-delete seed tasks `warm` / `chord` / `rhythm` / `song` / `four-done`
- Do not change Record Tab「查看详情」, History calendar, or statistics charts
- Copy language: `zh-Hans` via `String(localized:)` / String Catalog
- Unit test command: `xcodebuild -project foxgita.xcodeproj -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:foxgitaTests test` (swap simulator name if needed)
- YAGNI: no daily plan, no today「待练 / 已练」two-section layout, no cloud sync

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/PracticeRecordRules.swift` | `isUserAddedTask` + `isEffective` predicates |
| `foxgitaTests/PracticeRecordRulesTests.swift` | Predicate unit tests |
| `foxgita/Services/PracticeStore.swift` | Reject empty `finishSession`; seed/reset templates only |
| `foxgitaTests/PracticeStoreTests.swift` | Store cases for empty session + seed |
| `foxgita/Services/StatsAggregator.swift` | Effective-only week/streak; `DayTaskGroup` + `dayTaskGroups` |
| `foxgitaTests/StatsAggregatorTests.swift` | Aggregation + empty-day streak/week tests |
| `foxgita/App/AppRouter.swift` | `returnPracticeToToday` flag |
| `foxgita/Features/Practice/PracticeView.swift` | Inbox filter, past groups, 查看 → detail, toast |
| `foxgita/Components/SharedUI.swift` | `DaySessionCard` display fields (title/minutes/category) |
| `foxgita/Features/Practice/PracticeDetailView.swift` | Empty complete toast; stay on Practice tab; single submit |
| `foxgitaUITests/PracticeFlowUITests.swift` | Empty inbox + create-then-start smoke |
| `foxgita/Localizable.xcstrings` | New strings (Xcode may auto-extract) |
| `docs/TECHNICAL.md` | §4.1.1 / seed / `finishSession` notes |
| `foxgita/Services/SeedData.swift` | Leave `todayTasks()` in place; stop calling it |

---

### Task 1: PracticeRecordRules

**Files:**
- Create: `foxgita/Services/PracticeRecordRules.swift`
- Test: `foxgitaTests/PracticeRecordRulesTests.swift`

**Interfaces:**
- Consumes: nothing (pure `String` / `Int`)
- Produces:
  - `enum PracticeRecordRules`
  - `static func isUserAddedTask(id: String) -> Bool`
  - `static func isEffective(durationSec: Int, noteText: String, recordingCount: Int) -> Bool`
  - `extension TaskItem { var isUserAdded: Bool }`
  - `extension PracticeSession { var isEffective: Bool }`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/PracticeRecordRulesTests.swift`:

```swift
import Testing
@testable import foxgita

struct PracticeRecordRulesTests {
    @Test func userAddedAcceptsCustomAndActivePrefixes() {
        #expect(PracticeRecordRules.isUserAddedTask(id: "custom-abc"))
        #expect(PracticeRecordRules.isUserAddedTask(id: "active-tpl-chord"))
        #expect(PracticeRecordRules.isUserAddedTask(id: "warm") == false)
        #expect(PracticeRecordRules.isUserAddedTask(id: "chord") == false)
        #expect(PracticeRecordRules.isUserAddedTask(id: "song") == false)
    }

    @Test func effectiveRequiresTimeNoteOrRecording() {
        #expect(
            PracticeRecordRules.isEffective(durationSec: 0, noteText: "", recordingCount: 0) == false
        )
        #expect(PracticeRecordRules.isEffective(durationSec: 60, noteText: "", recordingCount: 0))
        #expect(PracticeRecordRules.isEffective(durationSec: 0, noteText: "  有笔记  ", recordingCount: 0))
        #expect(PracticeRecordRules.isEffective(durationSec: 0, noteText: "   ", recordingCount: 0) == false)
        #expect(PracticeRecordRules.isEffective(durationSec: 0, noteText: "", recordingCount: 1))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeRecordRulesTests \
  test
```

Expected: compile error — `PracticeRecordRules` not found.

- [ ] **Step 3: Minimal implementation**

Create `foxgita/Services/PracticeRecordRules.swift`:

```swift
import Foundation

enum PracticeRecordRules {
    static func isUserAddedTask(id: String) -> Bool {
        id.hasPrefix("custom-") || id.hasPrefix("active-")
    }

    static func isEffective(durationSec: Int, noteText: String, recordingCount: Int) -> Bool {
        if durationSec > 0 { return true }
        if !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return recordingCount > 0
    }
}

extension TaskItem {
    var isUserAdded: Bool { PracticeRecordRules.isUserAddedTask(id: id) }
}

extension PracticeSession {
    var isEffective: Bool {
        PracticeRecordRules.isEffective(
            durationSec: durationSec,
            noteText: noteText,
            recordingCount: recordings.count
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same `xcodebuild` command as Step 2.

Expected: PASS — `PracticeRecordRulesTests`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeRecordRules.swift foxgitaTests/PracticeRecordRulesTests.swift
git commit -m "$(cat <<'EOF'
feat: add shared rules for user-added tasks and effective sessions

EOF
)"
```

---

### Task 2: Store rejects empty sessions and seeds templates only

**Files:**
- Modify: `foxgita/Services/PracticeStore.swift` (`seedIfNeeded`, `finishSession`, `resetAll`)
- Modify: `foxgitaTests/PracticeStoreTests.swift`
- Test: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**
- Consumes: `PracticeRecordRules.isEffective(durationSec:noteText:recordingCount:)`
- Produces:
  - `finishSession` returns `false` and sets `lastError = .invalidInput` when the session is not effective
  - `seedIfNeeded()` / `resetAll()` write `SeedData.templates()` only (do not call `SeedData.todayTasks()`)

- [ ] **Step 1: Write the failing tests**

In `foxgitaTests/PracticeStoreTests.swift`, add these tests next to the existing session tests, and **replace** `resetAllRestoresSeededCatalogue` plus `finishSessionRollsBackWhenSaveFails` as shown (the rollback test must use a valid duration so it still reaches `save()`):

```swift
    @Test func finishSessionRejectsEmptySession() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        #expect(
            store.finishSession(
                taskId: "warm", steps: [], note: "",
                startedAt: now, endedAt: now, durationSec: 0, bpm: 80, recordings: []
            ) == false
        )
        #expect(store.lastError == .invalidInput)
        #expect(try repo.sessions().isEmpty)
    }

    @Test func finishSessionAcceptsZeroDurationWithNote() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        #expect(
            store.finishSession(
                taskId: "warm", steps: [], note: "只记一句",
                startedAt: now, endedAt: now, durationSec: 0, bpm: 80, recordings: []
            )
        )
        #expect(try repo.sessions().count == 1)
        #expect(try repo.sessions()[0].noteText == "只记一句")
    }

    @Test func seedIfNeededWritesOnlyTemplates() throws {
        let (store, repo, defaults) = makeStore(seeded: false)
        store.seedIfNeeded()
        #expect(defaults.bool(forKey: SeedData.seededKey))
        let tasks = try repo.tasks()
        #expect(tasks.allSatisfy(\.isTemplate))
        #expect(tasks.contains { $0.id == "warm" } == false)
        #expect(tasks.contains { $0.id.hasPrefix("tpl-") })
    }

    @Test func resetAllRestoresTemplatesOnly() throws {
        let (store, repo, defaults) = makeStore(seeded: true)
        try seedActive(into: repo, id: "custom-only")
        store.resetAll()
        #expect(defaults.bool(forKey: SeedData.seededKey))
        let tasks = try repo.tasks()
        #expect(tasks.contains { $0.id == "warm" } == false)
        #expect(tasks.contains { $0.isTemplate })
        #expect(tasks.contains { $0.id == "custom-only" } == false)
    }
```

Change `finishSessionRollsBackWhenSaveFails` to pass `durationSec: 60` (keep `note: ""`) so the session is effective and the save-failure path still runs.

Do **not** delete `seedOnlyRunsOnce`; it still holds when only templates are written.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests \
  test
```

Expected: FAIL — `finishSessionRejectsEmptySession` (currently persists), `seedIfNeededWritesOnlyTemplates` / `resetAllRestoresTemplatesOnly` (still writes `warm`).

- [ ] **Step 3: Minimal implementation**

In `foxgita/Services/PracticeStore.swift` `seedIfNeeded()`, delete the `todayTasks()` loop. Keep the templates loop:

```swift
    func seedIfNeeded() {
        guard !defaults.bool(forKey: SeedData.seededKey) else { return }
        perform {
            for template in SeedData.templates() { try repository.add(template) }
            try repository.save()
            defaults.set(true, forKey: SeedData.seededKey)
        }
    }
```

In `resetAll()`, delete the `todayTasks()` loop the same way:

```swift
    func resetAll() {
        perform {
            try repository.removeAll()
            for template in SeedData.templates() { try repository.add(template) }
            try repository.save()
            defaults.set(true, forKey: SeedData.seededKey)
            RecordingStore.removeAll()
        }
    }
```

In `finishSession`, after the existing `endedAt >= startedAt && durationSec >= 0` guard and **before** creating the `PracticeSession`, add:

```swift
        let existingClipCount = recordings.filter {
            FileManager.default.fileExists(atPath: $0.url.path)
        }.count
        guard PracticeRecordRules.isEffective(
            durationSec: durationSec,
            noteText: note,
            recordingCount: existingClipCount
        ) else {
            lastError = .invalidInput
            return false
        }
```

Leave `SeedData.todayTasks()` defined; nothing calls it after this task.

- [ ] **Step 4: Run tests to verify they pass**

Run the same `xcodebuild` command as Step 2.

Expected: PASS — all `PracticeStoreTests`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeStore.swift foxgitaTests/PracticeStoreTests.swift
git commit -m "$(cat <<'EOF'
fix: skip empty practice sessions and stop seeding today tasks

EOF
)"
```

---

### Task 3: StatsAggregator effective days and dayTaskGroups

**Files:**
- Modify: `foxgita/Services/StatsAggregator.swift` (`weekDays`, `streakDays`, `weekDots`, add `DayTaskGroup` + `dayTaskGroups`)
- Test: `foxgitaTests/StatsAggregatorTests.swift`

**Interfaces:**
- Consumes: `PracticeSession.isEffective`
- Produces:
  - `struct DayTaskGroup: Identifiable, Equatable` with `taskId: String`, `title: String`, `totalMinutes: Int`, `category: PracticeCategory`, `id` == `taskId`
  - `static func dayTaskGroups(sessions:on:calendar:) -> [DayTaskGroup]`
  - `weekDays` / `streakDays` / `weekDots` treat a day as practiced only when it has at least one effective session
  - Do **not** change `aggregate`, `daySummaries`, `totalMinutes`, or `minutesByDay` (Record / History stay as-is)

- [ ] **Step 1: Write the failing tests**

In `foxgitaTests/StatsAggregatorTests.swift`, extend `insertSession` with defaulted `taskTitle` and `note` so existing call sites compile:

```swift
    @discardableResult
    private func insertSession(
        endedAt: Date,
        minutes: Int,
        taskId: String = "task",
        taskTitle: String = "练习",
        note: String = "",
        category: PracticeCategory = .chord,
        into context: ModelContext
    ) -> PracticeSession {
        let session = PracticeSession(
            taskId: taskId,
            taskTitle: taskTitle,
            category: category,
            startedAt: endedAt.addingTimeInterval(-Double(minutes) * 60),
            endedAt: endedAt,
            durationSec: minutes * 60,
            bpm: 80,
            timeSig: "4/4",
            steps: [],
            noteText: note
        )
        context.insert(session)
        return session
    }
```

Add:

```swift
    @Test func weekDaysIgnoresIneffectiveSessions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let context = try makeContext()
        let tuesday = calendar.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 12))!
        let friday = calendar.date(from: DateComponents(year: 2023, month: 11, day: 17))!
        insertSession(endedAt: tuesday, minutes: 0, into: context)

        let days = StatsAggregator.weekDays(
            from: sessions(in: context),
            containing: tuesday,
            now: friday,
            calendar: calendar
        )
        #expect(days.filter(\.practiced).isEmpty)
    }

    @Test func streakIgnoresADayWithOnlyEmptySessions() throws {
        let context = try makeContext()
        insertSession(endedAt: day(0), minutes: 0, into: context)
        insertSession(endedAt: day(-1), minutes: 10, into: context)
        #expect(StatsAggregator.streakDays(from: sessions(in: context), now: Self.anchor) == 1)
    }

    @Test func dayTaskGroupsMergesEffectiveSessionsAndDropsEmpty() throws {
        let context = try makeContext()
        let dayStart = Calendar.current.startOfDay(for: Self.anchor)
        insertSession(
            endedAt: dayStart.addingTimeInterval(3600), minutes: 1,
            taskId: "song", taskTitle: "知足", into: context
        )
        insertSession(
            endedAt: dayStart.addingTimeInterval(7200), minutes: 1,
            taskId: "song", taskTitle: "知足", into: context
        )
        for offset in 3...6 {
            insertSession(
                endedAt: dayStart.addingTimeInterval(Double(offset) * 3600),
                minutes: 0, taskId: "song", taskTitle: "知足", into: context
            )
        }
        insertSession(
            endedAt: dayStart.addingTimeInterval(100), minutes: 10,
            taskId: "other", taskTitle: "音阶", into: context
        )

        let groups = StatsAggregator.dayTaskGroups(sessions: sessions(in: context), on: dayStart)
        #expect(groups.count == 2)
        let song = try #require(groups.first { $0.taskId == "song" })
        #expect(song.title == "知足")
        #expect(song.totalMinutes == 2)
        #expect(groups.contains { $0.taskId == "other" && $0.totalMinutes == 10 })
    }

    @Test func dayTaskGroupsKeepsZeroMinuteNoteOnlySession() throws {
        let context = try makeContext()
        let dayStart = Calendar.current.startOfDay(for: Self.anchor)
        insertSession(
            endedAt: dayStart.addingTimeInterval(60), minutes: 0,
            taskId: "song", taskTitle: "知足", note: "只写了笔记", into: context
        )
        let groups = StatsAggregator.dayTaskGroups(sessions: sessions(in: context), on: dayStart)
        #expect(groups.count == 1)
        #expect(groups[0].totalMinutes == 0)
        #expect(groups[0].title == "知足")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/StatsAggregatorTests \
  test
```

Expected: compile error — `dayTaskGroups` not found; `weekDaysIgnoresIneffectiveSessions` / `streakIgnoresADayWithOnlyEmptySessions` FAIL because empty sessions still count.

- [ ] **Step 3: Minimal implementation**

In `foxgita/Services/StatsAggregator.swift`, add this type next to `WeekDay`:

```swift
    struct DayTaskGroup: Identifiable, Equatable {
        var id: String { taskId }
        let taskId: String
        let title: String
        let totalMinutes: Int
        let category: PracticeCategory
    }
```

Add:

```swift
    static func dayTaskGroups(
        sessions: [PracticeSession],
        on day: Date,
        calendar: Calendar = .current
    ) -> [DayTaskGroup] {
        let effective = sessions.filter {
            $0.isEffective && calendar.isDate($0.endedAt, inSameDayAs: day)
        }
        let grouped = Dictionary(grouping: effective, by: \.taskId)
        return grouped.map { taskId, items in
            let latest = items.max(by: { $0.endedAt < $1.endedAt })!
            return DayTaskGroup(
                taskId: taskId,
                title: latest.taskTitle,
                totalMinutes: items.reduce(0) { $0 + $1.durationMinutes },
                category: latest.category
            )
        }
        .sorted { lhs, rhs in
            let left = grouped[lhs.taskId]!.map(\.endedAt).max()!
            let right = grouped[rhs.taskId]!.map(\.endedAt).max()!
            return left > right
        }
    }
```

Change the `practiced` line in `weekDays` to:

```swift
            let practiced = sessions.contains {
                $0.isEffective && calendar.isDate($0.endedAt, inSameDayAs: date)
            }
```

Change `streakDays` so the day set only includes effective sessions:

```swift
        let days = Set(
            sessions.filter(\.isEffective).map { cal.startOfDay(for: $0.endedAt) }
        )
```

Change the `practiced` line in `weekDots` to the same effective check as `weekDays`.

- [ ] **Step 4: Run tests to verify they pass**

Run the same `xcodebuild` command as Step 2.

Expected: PASS — all `StatsAggregatorTests`, including the new ones.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/StatsAggregator.swift foxgitaTests/StatsAggregatorTests.swift
git commit -m "$(cat <<'EOF'
feat: group past-day practice and ignore empty sessions in streaks

EOF
)"
```

---

### Task 4: PracticeView inbox, past groups, and 查看 → detail

**Files:**
- Modify: `foxgita/App/AppRouter.swift`
- Modify: `foxgita/Features/Practice/PracticeView.swift` (`activeTasks`, `taskList`, past-day open, toast)
- Modify: `foxgita/Components/SharedUI.swift` (`DaySessionCard`)
- Test: covered by Task 3 unit tests + Task 6 UI tests; this task is verified by building `foxgitaTests` and a manual checklist in Step 4

**Interfaces:**
- Consumes:
  - `TaskItem.isUserAdded`
  - `StatsAggregator.dayTaskGroups(sessions:on:)`
  - `AppRouter.practicePath` / `PracticeRoute.detail(taskId:)`
- Produces:
  - `AppRouter.returnPracticeToToday: Bool` (default `false`)
  - `AppRouter.practiceToast: String?` (default `nil`) — PracticeView presents this after detail pops
  - Today list = active + user-added tasks only
  - Past list = `DayTaskGroup` cards; tap opens `.detail(taskId)` when the task still exists
  - Missing task → Toast `练习已删除，无法再练`
  - `returnPracticeToToday == true` resets `selectedDay` and `weekAnchor` to the current week

- [ ] **Step 1: Add the router flag**

In `foxgita/App/AppRouter.swift`, add next to `openTodayFirstPractice`:

```swift
    /// Raised after a successful (or empty) complete so PracticeView snaps back to today.
    var returnPracticeToToday = false
    /// Set by detail / past-day open; PracticeView shows it then clears.
    var practiceToast: String?
```

- [ ] **Step 2: Let DaySessionCard render a group**

Replace `DaySessionCard` in `foxgita/Components/SharedUI.swift` with display fields, and keep a session convenience init so `SwipeableSessionRow` still compiles:

```swift
struct DaySessionCard: View {
    let title: String
    let minutes: Int
    let category: PracticeCategory
    var showsShadow: Bool = true
    var action: (() -> Void)?

    init(
        title: String,
        minutes: Int,
        category: PracticeCategory,
        showsShadow: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.minutes = minutes
        self.category = category
        self.showsShadow = showsShadow
        self.action = action
    }

    init(session: PracticeSession, showsShadow: Bool = true, action: (() -> Void)? = nil) {
        self.init(
            title: session.taskTitle,
            minutes: session.durationMinutes,
            category: session.category,
            showsShadow: showsShadow,
            action: action
        )
    }

    var body: some View {
        let card = HStack(spacing: 12) {
            Capsule()
                .fill(category.accent)
                .frame(width: 5)
                .frame(minHeight: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(GitaFont.body(.bold))
                    .foregroundStyle(GitaTheme.textPrimary)
                    .lineLimit(2)
                Text("已练 \(minutes) 分钟")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Text("查看")
                .font(GitaFont.caption(.semibold))
                .foregroundStyle(GitaTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(GitaTheme.bgSubtle)
                .clipShape(Capsule())
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(
            showsShadow
                ? AnyShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
                : AnyShape(Rectangle())
        )
        .shadow(color: showsShadow ? GitaTheme.shadowCard : .clear, radius: 8, y: 4)

        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(title)，已练 \(minutes) 分钟"))
        } else {
            card
        }
    }
}
```

- [ ] **Step 3: Filter today and open past groups in PracticeView**

In `foxgita/Features/Practice/PracticeView.swift`:

1. Add `@State private var toast: String?`.
2. Change `activeTasks` to:

```swift
    private var activeTasks: [TaskItem] {
        tasks.filter { $0.status == .active && $0.isUserAdded }
    }
```

3. Replace `daySessions` with:

```swift
    private var dayGroups: [StatsAggregator.DayTaskGroup] {
        StatsAggregator.dayTaskGroups(sessions: sessions, on: selectedDay)
    }
```

4. In `sectionMeta` for a past day, use `dayGroups.count` instead of `daySessions.count`.
5. In `taskList`, replace the `ForEach(daySessions)` / `SwipeableSessionRow` branch with:

```swift
            ForEach(dayGroups) { group in
                DaySessionCard(
                    title: group.title,
                    minutes: group.totalMinutes,
                    category: group.category
                ) {
                    openPastGroup(group)
                }
            }
```

and change the empty check from `daySessions.isEmpty` to `dayGroups.isEmpty`.

6. Add:

```swift
    private func openPastGroup(_ group: StatsAggregator.DayTaskGroup) {
        if tasks.contains(where: { $0.id == group.taskId }) {
            router.practicePath.append(.detail(taskId: group.taskId))
        } else {
            showToast(String(localized: "练习已删除，无法再练"))
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
```

7. Overlay `ToastBanner` on the `ZStack` when `toast != nil` (same placement as `PracticeDetailView`).
8. After the existing `onChange(of: router.openTodayFirstPractice)` block, add:

```swift
            .onChange(of: router.returnPracticeToToday) { _, requested in
                guard requested else { return }
                router.returnPracticeToToday = false
                selectedDay = calendar.startOfDay(for: Date())
                weekAnchor = StatsAggregator.week().start
            }
            .onChange(of: router.practiceToast) { _, message in
                guard let message else { return }
                router.practiceToast = nil
                showToast(message)
            }
```

9. Leave `openTodayFirstPractice` as-is (still opens today's first inbox item; empty inbox stays on the empty state).
10. Leave the bottom「查看记录」button as `router.selectedTab = .record`.
11. You may leave `EditSessionSheet` / session swipe state in the file; past-day list no longer uses them.

- [ ] **Step 4: Build tests to verify the app still compiles**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests \
  test
```

Expected: PASS — existing unit tests plus Tasks 1–3.

Manual check (do not skip): today list has no「指尖热身」; a past day with several empty completes of one song shows one card; tapping 查看 opens Practice detail, not the Record tab title「练习记录」.

- [ ] **Step 5: Commit**

```bash
git add foxgita/App/AppRouter.swift \
  foxgita/Features/Practice/PracticeView.swift \
  foxgita/Components/SharedUI.swift
git commit -m "$(cat <<'EOF'
feat: show a user inbox today and open practice from past-day cards

EOF
)"
```

---

### Task 5: PracticeDetailView complete stays on Practice

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` (`complete`, add `isCompleting`)

**Interfaces:**
- Consumes:
  - `PracticeStore.finishSession(...)` (now rejects empty sessions)
  - `hasUnsavedWork` (already: elapsed > 0 or pending clips or non-empty note)
  - `AppRouter.returnPracticeToToday`
- Produces:
  - Empty complete: no `finishSession`; set `router.practiceToast` to `这次没有留下记录` (PracticeView shows it after pop); `practicePath` cleared; `returnPracticeToToday = true`; `selectedTab` unchanged
  - Successful complete: same navigation; **do not** set `selectedTab = .record`
  - Failed `finishSession`: stay on detail; existing `store.lastError` toast
  - Second tap while `isCompleting == true` is ignored

- [ ] **Step 1: Add the completing guard and rewrite `complete`**

In `foxgita/Features/Practice/PracticeDetailView.swift`, add `@State private var isCompleting = false` with the other `@State` properties.

Replace `complete(_:)` with:

```swift
    private func complete(_ task: TaskItem) {
        guard !isCompleting else { return }
        isCompleting = true

        if recorder.isRecording { recorder.stop(label: task.title) }
        practiceTimer.pause()
        metronome.stop()

        if !hasUnsavedWork {
            router.practiceToast = String(localized: "这次没有留下记录")
            router.returnPracticeToToday = true
            router.practicePath.removeAll()
            return
        }

        var clips = recorder.consume()
        clips += video.takeAll().map {
            AudioRecorderService.Clip(
                id: $0.id,
                fileName: $0.fileName,
                bytes: $0.bytes,
                durationSec: $0.durationSec,
                createdAt: $0.createdAt,
                label: $0.label
            )
        }

        let end = Date()
        let elapsed = practiceTimer.elapsedSec
        let saved = store.finishSession(
            taskId: task.id,
            steps: steps,
            note: noteText,
            startedAt: practiceTimer.startedAt ?? end.addingTimeInterval(TimeInterval(-elapsed)),
            endedAt: end,
            durationSec: elapsed,
            bpm: metronome.bpm,
            recordings: clips
        )
        guard saved else {
            isCompleting = false
            return
        }
        Haptics.success()
        router.returnPracticeToToday = true
        router.practicePath.removeAll()
    }
```

Delete the line `router.selectedTab = .record`.

Keep `requestExit` / `leave` / confirmation dialog unchanged.

- [ ] **Step 2: Build unit tests**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests \
  test
```

Expected: PASS.

Manual check: open a task, tap「完成」immediately → toast「这次没有留下记录」, land on「今日练习」, Record tab is not selected. Open a task, run the timer, tap「完成」→ still on Practice tab, week calendar on today.

- [ ] **Step 3: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift
git commit -m "$(cat <<'EOF'
fix: keep completed practice on the practice tab

EOF
)"
```

---

### Task 6: UI smoke and TECHNICAL.md

**Files:**
- Modify: `foxgitaUITests/PracticeFlowUITests.swift`
- Modify: `docs/TECHNICAL.md` (§4.1.1 homepage table, §6.3 `seedIfNeeded` / `finishSession`)

**Interfaces:**
- Consumes: Task 4 empty inbox + RecommendSheet「创建练习」
- Produces: UI tests that match the new first-run empty today list

- [ ] **Step 1: Update UI tests**

In `foxgitaUITests/PracticeFlowUITests.swift`, replace `testStartFirstTaskOpensDetail` (there is no seeded「开始」card anymore) and add a seed-title assertion to `testLaunchShowsTodayPractice`:

```swift
    func testLaunchShowsTodayPractice() {
        XCTAssertTrue(app.staticTexts["今日练习"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今天只练一点点"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "连续练习"))
                .firstMatch.exists
        )
        XCTAssertTrue(app.descendants(matching: .any)["week-pager"].exists)
        XCTAssertFalse(app.staticTexts["指尖热身"].exists)
        XCTAssertFalse(app.staticTexts["和弦转换"].exists)
    }

    func testCreateCustomTaskOpensDetail() {
        let add = app.buttons["添加练习"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts["推荐练习"].waitForExistence(timeout: 5))

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("知足前奏")

        app.buttons["创建练习"].tap()
        XCTAssertTrue(app.staticTexts["节拍器"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成"].exists || app.staticTexts["完成本次练习"].exists)
    }

    func testEmptyCompleteStaysOnPracticeTab() {
        let add = app.buttons["添加练习"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("空完成")
        app.buttons["创建练习"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        XCTAssertTrue(app.staticTexts["今日练习"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["练习记录"].exists)
    }
```

Keep `testRecommendSheetCanBeOpenedAndDismissed`, `testRecommendSheetShowsImageGenerateEntry`, and `testSettingsAppearanceSegmentExists`.

- [ ] **Step 2: Run UI tests**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaUITests/PracticeFlowUITests \
  test
```

Expected: PASS. If the first-run simulator already has old seed data, erase the simulator (or delete the app) and re-run — leftover `warm` / `chord` tasks are excluded from today by id prefix, so「指尖热身」must not appear even on an upgraded store.

- [ ] **Step 3: Update TECHNICAL.md**

In `docs/TECHNICAL.md` §4.1.1, replace the homepage table with:

| 选中日 | 列表内容 | FAB 添加 | 左滑编辑/删除 | 进入详情 |
|---|---|---|---|---|
| **今天** | `status == .active` 且 id 为 `custom-*` / `active-*` 的任务 | 显示 | 有 | 「开始」→ 详情 |
| **过去** | 当天有效 session 按 `taskId` 聚合（`DayTaskGroup`） | 隐藏 | 无 | 「查看」→ 练习详情（新记录记今天） |
| **未来** | 空态「这一天还没到」 | 隐藏 | 无 | 不可练 |

有效记录：`durationSec > 0`，或笔记非空，或至少一条录音/视频。空完成不落库、不点亮周历。

In §6.3:

- `seedIfNeeded()` / `resetAll()`：只写入模板，不写入 `todayTasks()`
- `finishSession(...)`：在原有窗口校验之外，无效记录（0 秒且无笔记/录音）返回 `false` 并设 `.invalidInput`

In the complete-practice flowchart (around §4.1), change「切到记录 Tab」to「回到今天的练习列表」.

- [ ] **Step 4: Commit**

```bash
git add foxgitaUITests/PracticeFlowUITests.swift docs/TECHNICAL.md
git commit -m "$(cat <<'EOF'
test: smoke the empty inbox and document practice-tab rules

EOF
)"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| §2 today / past / future page rules | 4 |
| §3.1 user-added inbox | 1, 4 |
| §3.2 past-day aggregation + empty drop | 3, 4 |
| §3.3 streak / week n/7 | 3 |
| §4.1 查看 → practice detail; deleted toast | 4 |
| §4.1 Record「查看详情」unchanged | 4 (do not touch) |
| §4.2 complete stays on Practice; empty toast | 5 |
| §4.2 double-tap complete | 5 `isCompleting` |
| §4.3 / §5 seed templates only; no soft-delete | 2 |
| §7 finishSession notFound / invalid window | already in store; empty → `.invalidInput` in 2 |
| §8 unit tests | 1, 2, 3 |
| §8 UI smoke | 6 |
| §9 Record / History out of scope | 3 leaves `aggregate` / `daySummaries` alone |
