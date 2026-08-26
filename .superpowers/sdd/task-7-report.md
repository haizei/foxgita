# Task 7 Report: 将详情页改为 PracticeItem 单模型编辑

**Status:** DONE_WITH_CONCERNS  
**Branch:** `codex/practice-home-daily-items`  
**Commit:** (filled after commit) `refactor: edit practice items directly`

## What you implemented

Practice detail loads one `PracticeItem` by id. Timer starts from `durationSeconds`. Save is absolute `savePracticeItem`. No sessions are created or restored.

- `PracticeRoute.detail(itemId: UUID)`. `RecordRoute.detail(taskId:)` unchanged.
- `PracticeView` navigates with `item.id`. RecommendSheet still returns a `String`; `PracticeDetailState.practiceRoute(fromSheetSelection:)` parses UUID and skips navigation if parse fails.
- `PracticeDetailView(itemId: UUID)` queries that item only. Removed `@Query` sessions, `openSessionId`, `PracticeResumeQuery`, and `PracticeResumeSkipStore`.
- `PracticeDetailMode.editable` when `practiceDayKey` equals today's `PracticeDayKey`; `.historical` otherwise. Historical: no timer start, no auto-write on disappear; note, recordings, and review still show.
- Editable save / dirty `onDisappear` call `savePracticeItem(id:durationSeconds:note:now:)`. Same payload twice is not dirty, so it does not accumulate.
- Recordings attach via `attachRecording` onto the item. 25th-day open uses the requested id, independent of today and of same-title items.

Did not rewrite RecommendSheet/Photo/Next creation (Task 8). Did not edit `project.pbxproj` or `Localizable.xcstrings`.

## Files

| Action | Path |
|---|---|
| Modified | `foxgita/App/AppRouter.swift` |
| Modified | `foxgita/Features/Practice/PracticeDetailView.swift` |
| Modified | `foxgitaTests/AppRouterTests.swift` |
| Created | `foxgitaTests/PracticeDetailStateTests.swift` |
| Modified (extra, required) | `foxgita/Features/Practice/PracticeView.swift` |

`PracticeView.swift` is required so `navigationDestination` and append sites pass `UUID`.

## TDD Evidence

### RED (route payload / helper missing)

Command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AppRouterTests \
  -only-testing:foxgitaTests/PracticeDetailStateTests \
  test
```

Failing output (compile-time RED):

```
AppRouterTests.swift:15:41: error: incorrect argument label in call (have 'itemId:', expected 'taskId:')
AppRouterTests.swift:15:50: error: cannot convert value of type 'UUID' to expected argument type 'String'
AppRouterTests.swift:25:21: error: cannot find 'PracticeDetailState' in scope
Testing cancelled because the build failed.
** TEST FAILED **
```

Exit code 65. Production types were not changed until this RED was captured.

### GREEN (same command after implementations)

```
✔ Test historicalDoesNotAutoWriteEvenWhenDirty() passed
✔ Test clearJustCompletedDropsSessionId() passed
✔ Test timerStartsFromStoredDurationSeconds() passed
✔ Test detailMatchesHomeItem() passed
✔ Test practiceDetailRouteCarriesItemId() passed
✔ Test homeNavigatesByPracticeItemId() passed
✔ Test historicalDayIsReadOnly() passed
✔ Test recordDetailRouteStillUsesTaskId() passed
✔ Test samePayloadTwiceIsNotDirty() passed
✔ Test todayItemIsEditable() passed
✔ Test twentyFifthDayItemOpensIndependentOfTodayAndSameTitle() passed
✔ Test editableSavesWhenDirtyAndSkipsClean() passed
✔ Test invalidRecommendSelectionDoesNotNavigate() passed
✔ Suite PracticeDetailStateTests passed after 0.009 seconds.
✔ Suite AppRouterTests passed after 0.009 seconds.
✔ Test run with 13 tests in 2 suites passed after 0.010 seconds.
** TEST SUCCEEDED **
```

13 tests in 2 suites, all passing. App compile included `PracticeView` / `PracticeDetailView` route call sites. `PracticeStore` was not changed; existing save overwrite tests were not re-run.

## New tests

| Test | Behavior |
|---|---|
| `practiceDetailRouteCarriesItemId` | `PracticeRoute.detail(itemId:)` holds a UUID |
| `homeNavigatesByPracticeItemId` | Home path is `.detail(itemId:)` |
| `invalidRecommendSelectionDoesNotNavigate` | Non-UUID sheet strings do not form a route |
| `recordDetailRouteStillUsesTaskId` | Record tab still uses `taskId: String` |
| `todayItemIsEditable` | Today's day key is `.editable` and timer allowed |
| `historicalDayIsReadOnly` | Other day key is `.historical`; no timer, no auto-save |
| `historicalDoesNotAutoWriteEvenWhenDirty` | Dirty historical still does not auto-save |
| `editableSavesWhenDirtyAndSkipsClean` | Editable saves only when dirty |
| `timerStartsFromStoredDurationSeconds` | Initial elapsed is stored duration (clamped ≥ 0) |
| `samePayloadTwiceIsNotDirty` | Identical duration+note is not dirty |
| `detailMatchesHomeItem` | Detail loads the same id / day key / title as the home row |
| `twentyFifthDayItemOpensIndependentOfTodayAndSameTitle` | 25th item id stays 25th; same title on 26th is ignored |

## Self-review

- Completeness: route is itemId; detail queries one item; historical is read-only for timer/save; recordings/review remain; Record routes unchanged.
- YAGNI: no RecommendSheet rewrite; no session restore; no pbxproj/strings.
- TDD: compile-time RED then GREEN on the same two-suite command.

## Concerns

- **RecommendSheet still returns TaskItem string ids** until Task 8. `UUID(uuidString:)` fails, so create-from-sheet does not open detail. UITests `testCreateCustomTaskOpensDetail` and `testEmptyCompleteStaysOnPracticeTab` will fail until Task 8.
- PracticeItem has no steps; the steps card was removed. Metronome/video UI was kept. BPM is not persisted (`savePracticeItem` only takes duration and note).
- RESET discards unsaved timer/note changes (restores stored values). It no longer seals a session and starts a new trip from 0.
- Extra file: `PracticeView.swift` (required route call sites). Brief listed four files.
