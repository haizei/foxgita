# Task 5 Report: 将录音归属切到 PracticeItem

**Status:** DONE_WITH_CONCERNS  
**Branch:** `codex/practice-home-daily-items`  
**Commit:** `32dc9e9` `feat: attach recordings to practice items`

## What you implemented

New recordings attach to `PracticeItem` only. No empty `PracticeSession` is created. Review dual-reads: prefer `practiceItem`, else legacy `session`.

- `PracticeStore.attachRecording(_:toPracticeItemId:)` requires the clip file on disk, sets `recording.session = nil`, appends to `item.recordings`, and saves with the item. Throws `.fileMissing` / `.notFound`.
- `PracticeReviewContext` (`.practiceItem(UUID)` / `.legacySession(UUID)`) plus `practiceReviewContext(recordingId:)`. `reviewContext` still returns `MediaReviewContext` (item title/bpm/timeSignature/note, or legacy session fields) so ReviewJobRunner keeps working.
- `RecordingStore.referencedFileNames(practiceItems:sessions:)` unions both relationship file names. `gcOrphanRecordings` uses it so launch GC does not delete new item clips. Soft-deleted items still protect their files (`practiceItemsIncludingDeleted`).
- InMemory cascade equivalent: `removePracticeItem(id:)` drops the item object; `recording(id:)` no longer finds its clips. Soft-delete does not cascade.
- Did not migrate old session recordings onto items. Did not edit `project.pbxproj` or `Localizable.xcstrings`.

## Files

| Action | Path |
|---|---|
| Modified | `foxgita/Services/RecordingStore.swift` |
| Modified | `foxgita/Services/PracticeStore.swift` |
| Modified | `foxgitaTests/RecordingStoreTests.swift` |
| Modified | `foxgitaTests/PracticeStoreTests.swift` |
| Modified (extra, required) | `foxgita/Services/PracticeRepository.swift` |

Committed all five. The extra file is required for attach/query/GC: InMemory `recording(id:)` now searches `PracticeItem.recordings`; protocol gained `practiceItemsIncludingDeleted()`; InMemory `removePracticeItem(id:)` implements cascade for tests.

## TDD Evidence

### RED (APIs missing)

Command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/RecordingStoreTests \
  -only-testing:foxgitaTests/PracticeStoreTests \
  test
```

Failing output (compile-time RED):

```
RecordingStoreTests.swift:46:41: error: type 'RecordingStore' has no member 'referencedFileNames'
RecordingStoreTests.swift:90:41: error: type 'RecordingStore' has no member 'referencedFileNames'
Testing cancelled because the build failed.
** TEST FAILED **
```

Exit code 65. Production types were not changed until this RED was captured.

### GREEN (same command after implementations)

```
✔ Test attachRecordingDoesNotCreateSession() passed
✔ Test deletingPracticeItemCascadesItsRecordings() passed
✔ Test legacySessionRecordingsRemainReadable() passed
✔ Test attachRecordingMissingFileDoesNotWrite() passed
✔ Test gcOrphanRecordingsKeepsPracticeItemClips() passed
✔ Test referencedFileNamesIncludePracticeItemAndSessionRecordings() passed
✔ Test removeOrphansKeepsPracticeItemAndSessionClips() passed
✔ Suite RecordingStoreTests passed after 0.133 seconds.
✔ Suite PracticeStoreTests passed after 0.146 seconds.
✔ Test run with 68 tests in 2 suites passed after 0.146 seconds.
** TEST SUCCEEDED **
```

68 tests in 2 suites, all passing (existing tests plus 5 PracticeStore + 2 RecordingStore ownership/GC tests).

## New tests

| Test | Behavior |
|---|---|
| `attachRecordingDoesNotCreateSession` | Item clip has nil session; no new PracticeSession; `practiceReviewContext` is `.practiceItem` |
| `deletingPracticeItemCascadesItsRecordings` | Hard-remove item drops lookup of its recordings |
| `legacySessionRecordingsRemainReadable` | Session clip still readable; context is `.legacySession` |
| `attachRecordingMissingFileDoesNotWrite` | Missing file throws `.fileMissing`; no row |
| `gcOrphanRecordingsKeepsPracticeItemClips` | Launch-style GC keeps item clip, deletes orphan |
| `referencedFileNamesIncludePracticeItemAndSessionRecordings` | Helper unions both relationships |
| `removeOrphansKeepsPracticeItemAndSessionClips` | Disk GC respects the helper set |

## Self-review

- Completeness: new write is item-only; review distinguishes item vs legacy session; MediaReviewContext payload kept; GC covers both relationships; InMemory lookup + cascade equivalent; legacy session path unchanged.
- YAGNI: no migration of old session clips; no empty session; no pbxproj/strings.
- TDD: compile-time RED then GREEN on the same two-suite command.

## Concerns

- **Extra file:** `PracticeRepository.swift` was required and included in the commit (InMemory `recording(id:)` previously searched sessions only; GC needs `practiceItemsIncludingDeleted()` so soft-deleted items do not lose files). Brief listed four files; correctness required the fifth.
- Cascade is hard-delete of the item object (`removePracticeItem`), not `deletedAt`. Soft-delete keeps the RecordingRef row and the on-disk clip.
- `PracticeItem` has no `steps`; item `MediaReviewContext.steps` is `[]`. BPM/time signature use optional item fields (`?? 0` / `?? ""`).
- Tests exercise InMemory only. SwiftData cascade is the schema `deleteRule: .cascade` on `PracticeItem.recordings`.

---

## Review fix: fail-closed recording GC

**Status:** FIXED  
**Commit message:** `fix: fail closed when recording GC cannot load rows`

`gcOrphanRecordings()` treated a failed `sessions()` / `practiceItemsIncludingDeleted()` fetch as `[]`, which could delete item-owned clips on launch. It now returns 0 and skips `removeOrphans` if either fetch fails. InMemory gained a `fetchError` hook so the getters can throw.

Left as Minor: cascade via `removePracticeItem` vs `softDelete`; `attachRecording` not bumping `updatedAt`.

### Covering tests

`foxgitaTests/PracticeStoreTests.swift`  
`foxgitaTests/RecordingStoreTests.swift`

### Command

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/RecordingStoreTests \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

### Output

```
✔ Test gcOrphanRecordingsKeepsPracticeItemClips() passed after 0.127 seconds.
✔ Test gcOrphanRecordingsReturnsZeroWhenFetchFails() passed after 0.127 seconds.
✔ Suite RecordingStoreTests passed after 0.127 seconds.
✔ Suite PracticeStoreTests passed after 0.154 seconds.
✔ Test run with 69 tests in 2 suites passed after 0.154 seconds.
** TEST SUCCEEDED **
```
